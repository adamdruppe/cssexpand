/**
	This is the helper functions for cssexpand,
	extracted from html.d.
*/
module arsd.css;

import arsd.color;

import std.exception;
import std.conv;
import std.string;
import std.array;
import std.uri;
import std.range;

abstract class CssPart {
	override string toString() const;
	CssPart clone() const;
}

class CssAtRule : CssPart {
	this() {}
	this(ref string css) {
		assert(css.length);
		assert(css[0] == '@');

		int braceCount = 0;
		int startOfInnerSlice = -1;

		foreach(i, c; css) {
			if(braceCount == 0 && c == ';') {
				content = css[0 .. i + 1];
				css = css[i + 1 .. $];

				opener = content;
				break;
			}

			if(c == '{') {
				braceCount++;
				if(startOfInnerSlice == -1)
					startOfInnerSlice = i;
			}
			if(c == '}') {
				braceCount--;
				if(braceCount < 0)
					throw new Exception("Bad CSS: mismatched }");

				if(braceCount == 0) {
					opener = css[0 .. startOfInnerSlice];
					inner = css[startOfInnerSlice + 1 .. i];

					content = css[0 .. i + 1];
					css = css[i + 1 .. $];
					break;
				}
			}
		}
	}

	string content;

	string opener;
	string inner;

	override CssAtRule clone() const {
		auto n = new CssAtRule();
		n.content = content;
		n.opener = opener;
		n.inner = inner;
		return n;
	}
	override string toString() const { return content; }
}

class CssRuleSet : CssPart {
	this() {}

	this(ref string css) {
		auto idx = css.indexOf("{");
		assert(idx != -1);
		foreach(selector; css[0 .. idx].split(","))
			selectors ~= selector.strip;

		css = css[idx .. $];
		int braceCount = 0;
		string content;
		size_t f = css.length;
		foreach(i, c; css) {
			if(c == '{')
				braceCount++;
			if(c == '}') {
				braceCount--;
				if(braceCount == 0) {
					f = i;
					break;
				}
			}
		}

		content = css[1 .. f]; // skipping the {
		if(f < css.length && css[f] == '}')
			f++;
		css = css[f .. $];

		contents = lexCss(content);
	}

	string[] selectors;
	CssPart[] contents;

	override CssRuleSet clone() const {
		auto n = new CssRuleSet();
		n.selectors = selectors.dup;
		foreach(part; contents)
			n.contents ~= part.clone();
		return n;
	}

	CssRuleSet[] deNest(CssRuleSet outer = null) const {
		CssRuleSet[] ret;

		CssRuleSet levelOne = new CssRuleSet();
		ret ~= levelOne;
		if(outer is null)
			levelOne.selectors = selectors.dup;
		else {
			foreach(outerSelector; outer.selectors.length ? outer.selectors : [""])
			foreach(innerSelector; selectors) {
				/*
					it would be great to do a top thing and a bottom, examples:
					.awesome, .awesome\& {
						.something img {}
					}

					should give:
						.awesome .something img, .awesome.something img { }

					And also
					\&.cool {
						.something img {}
					}

					should give:
						.something img.cool {}

					OR some such syntax.


					The idea though is it will ONLY apply to end elements with that particular class. Why is this good? We might be able to isolate the css more for composited files.

					idk though.
				*/
				/+
				// FIXME: this implementation is useless, but the idea of allowing combinations at the top level rox.
				if(outerSelector.length > 2 && outerSelector[$-2] == '\\' && outerSelector[$-1] == '&') {
					// the outer one is an adder... so we always want to paste this on, and if the inner has it, collapse it
					if(innerSelector.length > 2 && innerSelector[0] == '\\' && innerSelector[1] == '&')
						levelOne.selectors ~= outerSelector[0 .. $-2] ~ innerSelector[2 .. $];
					else
						levelOne.selectors ~= outerSelector[0 .. $-2] ~ innerSelector;
				} else
				+/

				// we want to have things like :hover, :before, etc apply without implying
				// a descendant.

				// If you want it to be a descendant pseudoclass, use the *:something - the
				// wildcard tag - instead of just a colon.

				// But having this is too useful to ignore.
				if(innerSelector.length && innerSelector[0] == ':')
					levelOne.selectors ~= outerSelector ~ innerSelector;
				// we also allow \&something to get them concatenated
				else if(innerSelector.length > 2 && innerSelector[0] == '\\' && innerSelector[1] == '&')
					levelOne.selectors ~= outerSelector ~ innerSelector[2 .. $].strip;
				else
					levelOne.selectors ~= outerSelector ~ " " ~ innerSelector; // otherwise, use some other operator...
			}
		}

		foreach(part; contents) {
			auto set = cast(CssRuleSet) part;
			if(set is null)
				levelOne.contents ~= part.clone();
			else {
				// actually gotta de-nest this
				ret ~= set.deNest(levelOne);
			}
		}

		return ret;
	}

	override string toString() const {
		string ret;

		bool outputtedSelector = false;
		foreach(selector; selectors) {
			if(outputtedSelector)
				ret ~= ", ";
			else
				outputtedSelector = true;

			ret ~= selector;
		}

		ret ~= " {\n";
		foreach(content; contents) {
			auto str = content.toString();
			if(str.length)
				str = "\t" ~ str.replace("\n", "\n\t") ~ "\n";

			ret ~= str;
		}
		ret ~= "}";

		return ret;
	}
}

class CssRule : CssPart {
	this() {}

	this(ref string css, int endOfStatement) {
		content = css[0 .. endOfStatement];
		if(endOfStatement < css.length && css[endOfStatement] == ';')
			endOfStatement++;

		css = css[endOfStatement .. $];
	}

	// note: does not include the ending semicolon
	string content;

	override CssRule clone() const {
		auto n = new CssRule();
		n.content = content;
		return n;
	}

	override string toString() const {
		if(strip(content).length == 0)
			return "";
		return content ~ ";";
	}
}

CssPart[] lexCss(string css) {
	import std.regex;
	// strips comments
	css = std.regex.replace(css, regex(r"\/\*[^*]*\*+([^/*][^*]*\*+)*\/", "g"), "");

	CssPart[] ret;
	css = css.stripLeft();

	while(css.length > 1) {
		CssPart p;

		if(css[0] == '@') {
			p = new CssAtRule(css);
		} else {
			// non-at rules can be either rules or sets.
			// The question is: which comes first, the ';' or the '{' ?

			auto endOfStatement = css.indexOf(";");
			if(endOfStatement == -1)
				endOfStatement = css.indexOf("}");
			if(endOfStatement == -1)
				endOfStatement = css.length;

			auto beginningOfBlock = css.indexOf("{");
			if(beginningOfBlock == -1 || endOfStatement < beginningOfBlock)
				p = new CssRule(css, cast(int) endOfStatement);
			else
				p = new CssRuleSet(css);
		}

		assert(p !is null);
		ret ~= p;

		css = css.stripLeft();
	}

	return ret;
}

string cssToString(in CssPart[] css) {
	string ret;
	foreach(c; css) {
		if(ret.length) {
			if(ret[$ -1] == '}')
				ret ~= "\n\n";
			else
				ret ~= "\n";
		}
		ret ~= c.toString();
	}

	return ret;
}

/// Translates nested css
const(CssPart)[] denestCss(CssPart[] css) {
	CssPart[] ret;
	foreach(part; css) {
		auto at = cast(CssAtRule) part;
		if(at is null) {
			auto set = cast(CssRuleSet) part;
			if(set is null)
				ret ~= part;
			else {
				ret ~= set.deNest();
			}
		} else {
			// at rules with content may be denested at the top level...
			// FIXME: is this even right all the time?

			if(at.inner.length) {
				auto newCss = at.opener ~ "{\n";

					// the whitespace manipulations are just a crude indentation thing
				newCss ~= "\t" ~ (cssToString(denestCss(lexCss(at.inner))).replace("\n", "\n\t").replace("\n\t\n\t", "\n\n\t"));

				newCss ~= "\n}";

				ret ~= new CssAtRule(newCss);
			} else {
				ret ~= part; // no inner content, nothing special needed
			}
		}
	}

	return ret;
}

/*
	Forms:

	¤var
	¤lighten(¤foreground, 0.5)
	¤lighten(¤foreground, 0.5); -- exactly one semicolon shows up at the end
	¤var(something, something_else) {
		final argument
	}

	¤function {
		argument
	}


	Possible future:

	Recursive macros:

	¤define(li) {
		<li>¤car</li>
		list(¤cdr)
	}

	¤define(list) {
		¤li(¤car)
	}


	car and cdr are borrowed from lisp... hmm
	do i really want to do this...



	But if the only argument is cdr, and it is empty the function call is cancelled.
	This lets you do some looping.


	hmmm easier would be

	¤loop(macro_name, args...) {
		body
	}

	when you call loop, it calls the macro as many times as it can for the
	given args, and no more.



	Note that set is a macro; it doesn't expand it's arguments.
	To force expansion, use echo (or expand?) on the argument you set.
*/

// Keep in mind that this does not understand comments!
class MacroExpander {
	dstring delegate(dstring[])[dstring] functions;
	dstring[dstring] variables;

	/// This sets a variable inside the macro system
	void setValue(string key, string value) {
		variables[to!dstring(key)] = to!dstring(value);
	}

	struct Macro {
		dstring name;
		dstring[] args;
		dstring definition;
	}

	Macro[dstring] macros;

	// FIXME: do I want user defined functions or something?

	this() {
		functions["get"] = &get;
		functions["set"] = &set;
		functions["define"] = &define;
		functions["loop"] = &loop;

		functions["echo"] = delegate dstring(dstring[] args) {
			dstring ret;
			bool outputted;
			foreach(arg; args) {
				if(outputted)
					ret ~= ", ";
				else
					outputted = true;
				ret ~= arg;
			}

			return ret;
		};

		functions["uriEncode"] = delegate dstring(dstring[] args) {
			return to!dstring(std.uri.encodeComponent(to!string(args[0])));
		};

		functions["test"] = delegate dstring(dstring[] args) {
			assert(0, to!string(args.length) ~ " args: " ~ to!string(args));
		};

		functions["include"] = &include;
	}

	string[string] includeFiles;

	dstring include(dstring[] args) {
		string s;
		foreach(arg; args) {
			string lol = to!string(arg);
			s ~= to!string(includeFiles[lol]);
		}

		return to!dstring(s);
	}

	// the following are used inside the user text

	dstring define(dstring[] args) {
		enforce(args.length > 1, "requires at least a macro name and definition");

		Macro m;
		m.name = args[0];
		if(args.length > 2)
			m.args = args[1 .. $ - 1];
		m.definition = args[$ - 1];

		macros[m.name] = m;

		return null;
	}

	dstring set(dstring[] args) {
		enforce(args.length == 2, "requires two arguments. got " ~ to!string(args));
		variables[args[0]] = args[1];
		return "";
	}

	dstring get(dstring[] args) {
		enforce(args.length == 1);
		if(args[0] !in variables)
			return "";
		return variables[args[0]];
	}

	dstring loop(dstring[] args) {
		enforce(args.length > 1, "must provide a macro name and some arguments");
		auto m = macros[args[0]];
		args = args[1 .. $];
		dstring returned;

		size_t iterations = args.length;
		if(m.args.length != 0)
			iterations = (args.length + m.args.length - 1) / m.args.length;

		foreach(i; 0 .. iterations) {
			returned ~= expandMacro(m, args);
			if(m.args.length < args.length)
				args = args[m.args.length .. $];
			else
				args = null;
		}

		return returned;
	}

	/// Performs the expansion
	string expand(string srcutf8) {
		auto src = expand(to!dstring(srcutf8));
		return to!string(src);
	}

	private int depth = 0;
	/// ditto
	dstring expand(dstring src) {
		return expandImpl(src, null);
	}

	// FIXME: the order of evaluation shouldn't matter. Any top level sets should be run
	// before anything is expanded.
	private dstring expandImpl(dstring src, dstring[dstring] localVariables) {
		depth ++;
		if(depth > 10)
			throw new Exception("too much recursion depth in macro expansion");

		bool doneWithSetInstructions = false; // this is used to avoid double checks each loop
		for(;;) {
			// we do all the sets first since the latest one is supposed to be used site wide.
			// this allows a later customization to apply to the entire document.
			auto idx = doneWithSetInstructions ? -1 : src.indexOf("¤set");
			if(idx == -1) {
				doneWithSetInstructions = true;
				idx = src.indexOf("¤");
			}
			if(idx == -1) {
				depth--;
				return src;
			}

			// the replacement goes
			// src[0 .. startingSliceForReplacement] ~ new ~ src[endingSliceForReplacement .. $];
			sizediff_t startingSliceForReplacement, endingSliceForReplacement;

			dstring functionName;
			dstring[] arguments;
			bool addTrailingSemicolon;

			startingSliceForReplacement = idx;
			// idx++; // because the star in UTF 8 is two characters. FIXME: hack -- not needed thx to dstrings
			auto possibility = src[idx + 1 .. $];
			size_t argsBegin;

			bool found = false;
			foreach(i, c; possibility) {
				if(!(
					// valid identifiers
					(c >= 'A' && c <= 'Z')
					||
					(c >= 'a' && c <= 'z')
					||
					(c >= '0' && c <= '9')
					||
					c == '_'
				)) {
					// not a valid identifier means
					// we're done reading the name
					functionName = possibility[0 .. i];
					argsBegin = i;
					found = true;
					break;
				}
			}

			if(!found) {
				functionName = possibility;
				argsBegin = possibility.length;
			}

			auto endOfVariable = argsBegin + idx + 1; // this is the offset into the original source

			bool checkForAllArguments = true;

			moreArguments:

			assert(argsBegin);

			endingSliceForReplacement = argsBegin + idx + 1;

			while(
				argsBegin < possibility.length && (
				possibility[argsBegin] == ' ' ||
				possibility[argsBegin] == '\t' ||
				possibility[argsBegin] == '\n' ||
				possibility[argsBegin] == '\r'))
			{
				argsBegin++;
			}

			if(argsBegin == possibility.length) {
				endingSliceForReplacement = src.length;
				goto doReplacement;
			}

			switch(possibility[argsBegin]) {
				case '(':
					if(!checkForAllArguments)
						goto doReplacement;

					// actually parsing the arguments
					size_t currentArgumentStarting = argsBegin + 1;

					int open;

					bool inQuotes;
					bool inTicks;
					bool justSawBackslash;
					foreach(i, c; possibility[argsBegin .. $]) {
						if(c == '`')
							inTicks = !inTicks;

						if(inTicks)
							continue;

						if(!justSawBackslash && c == '"')
							inQuotes = !inQuotes;

						if(c == '\\')
							justSawBackslash = true;
						else
							justSawBackslash = false;

						if(inQuotes)
							continue;

						if(open == 1 && c == ',') { // don't want to push a nested argument incorrectly...
							// push the argument
							arguments ~= possibility[currentArgumentStarting .. i + argsBegin];
							currentArgumentStarting = argsBegin + i + 1;
						}

						if(c == '(')
							open++;
						if(c == ')') {
							open--;
							if(open == 0) {
								// push the last argument
								arguments ~= possibility[currentArgumentStarting .. i + argsBegin];

								endingSliceForReplacement = argsBegin + idx + 1 + i;
								argsBegin += i + 1;
								break;
							}
						}
					}

					// then see if there's a { argument too
					checkForAllArguments = false;
					goto moreArguments;
				case '{':
					// find the match
					int open;
					foreach(i, c; possibility[argsBegin .. $]) {
						if(c == '{')
							open ++;
						if(c == '}') {
							open --;
							if(open == 0) {
								// cutting off the actual braces here
								arguments ~= possibility[argsBegin + 1 .. i + argsBegin];
									// second +1 is there to cut off the }
								endingSliceForReplacement = argsBegin + idx + 1 + i + 1;

								argsBegin += i + 1;
								break;
							}
						}
					}

					goto doReplacement;
				default:
					goto doReplacement;
			}

			doReplacement:
				if(endingSliceForReplacement < src.length && src[endingSliceForReplacement] == ';') {
					endingSliceForReplacement++;
					addTrailingSemicolon = true; // don't want a doubled semicolon
					// FIXME: what if it's just some whitespace after the semicolon? should that be
					// stripped or no?
				}

				foreach(ref argument; arguments) {
					argument = argument.strip();
					if(argument.length > 2 && argument[0] == '`' && argument[$-1] == '`')
						argument = argument[1 .. $ - 1]; // strip ticks here
					else
					if(argument.length > 2 && argument[0] == '"' && argument[$-1] == '"')
						argument = argument[1 .. $ - 1]; // strip quotes here

					// recursive macro expanding
					// these need raw text, since they expand later. FIXME: should it just be a list of functions?
					if(functionName != "define" && functionName != "quote" && functionName != "set")
						argument = this.expandImpl(argument, localVariables);
				}

				dstring returned = "";
				if(functionName in localVariables) {
					/*
					if(functionName == "_head")
						returned = arguments[0];
					else if(functionName == "_tail")
						returned = arguments[1 .. $];
					else
					*/
						returned = localVariables[functionName];
				} else if(functionName in functions)
					returned = functions[functionName](arguments);
				else if(functionName in variables) {
					returned = variables[functionName];
					// FIXME
					// we also need to re-attach the arguments array, since variable pulls can't have args
					assert(endOfVariable > startingSliceForReplacement);
					endingSliceForReplacement = endOfVariable;
				} else if(functionName in macros) {
					returned = expandMacro(macros[functionName], arguments);
				}

				if(addTrailingSemicolon && returned.length > 1 && returned[$ - 1] != ';')
					returned ~= ";";

				src = src[0 .. startingSliceForReplacement] ~ returned ~ src[endingSliceForReplacement .. $];
		}
		assert(0); // not reached
	}

	dstring expandMacro(Macro m, dstring[] arguments) {
		dstring[dstring] locals;
		foreach(i, arg; m.args) {
			if(i == arguments.length)
				break;
			locals[arg] = arguments[i];
		}

		return this.expandImpl(m.definition, locals);
	}
}


class CssMacroExpander : MacroExpander {
	this() {
		super();

		functions["prefixed"] = &prefixed;

		functions["lighten"] = &(colorFunctionWrapper!lighten);
		functions["darken"] = &(colorFunctionWrapper!darken);
		functions["moderate"] = &(colorFunctionWrapper!moderate);
		functions["extremify"] = &(colorFunctionWrapper!extremify);
		functions["makeTextColor"] = &(oneArgColorFunctionWrapper!makeTextColor);

		functions["oppositeLightness"] = &(oneArgColorFunctionWrapper!oppositeLightness);

		functions["rotateHue"] = &(colorFunctionWrapper!rotateHue);

		functions["saturate"] = &(colorFunctionWrapper!saturate);
		functions["desaturate"] = &(colorFunctionWrapper!desaturate);

		functions["setHue"] = &(colorFunctionWrapper!setHue);
		functions["setSaturation"] = &(colorFunctionWrapper!setSaturation);
		functions["setLightness"] = &(colorFunctionWrapper!setLightness);
	}

	// prefixed(border-radius: 12px);
	dstring prefixed(dstring[] args) {
		dstring ret;
		foreach(prefix; ["-moz-"d, "-webkit-"d, "-o-"d, "-ms-"d, "-khtml-"d, ""d])
			ret ~= prefix ~ args[0] ~ ";";
		return ret;
	}

	/// Runs the macro expansion but then a CSS densesting
	string expandAndDenest(string cssSrc) {
		return cssToString(denestCss(lexCss(this.expand(cssSrc))));
	}

	// internal things
	dstring colorFunctionWrapper(alias func)(dstring[] args) {
		auto color = readCssColor(to!string(args[0]));
		auto percentage = readCssNumber(args[1]);
		return "#"d ~ to!dstring(func(color, percentage).toString());
	}

	dstring oneArgColorFunctionWrapper(alias func)(dstring[] args) {
		auto color = readCssColor(to!string(args[0]));
		return "#"d ~ to!dstring(func(color).toString());
	}
}


real readCssNumber(dstring s) {
	s = s.replace(" "d, ""d);
	if(s.length == 0)
		return 0;
	if(s[$-1] == '%')
		return (to!real(s[0 .. $-1]) / 100f);
	return to!real(s);
}

import std.format;

class JavascriptMacroExpander : MacroExpander {
	this() {
		super();
		functions["foreach"] = &foreachLoop;
	}


	/**
		¤foreach(item; array) {
			// code
		}

		so arg0 .. argn-1 is the stuff inside. Conc
	*/

	int foreachLoopCounter;
	dstring foreachLoop(dstring[] args) {
		enforce(args.length >= 2, "foreach needs parens and code");
		dstring parens;
		bool outputted = false;
		foreach(arg; args[0 .. $ - 1]) {
			if(outputted)
				parens ~= ", ";
			else
				outputted = true;
			parens ~= arg;
		}

		dstring variableName, arrayName;

		auto it = parens.split(";");
		variableName = it[0].strip;
		arrayName = it[1].strip;

		dstring insideCode = args[$-1];

		dstring iteratorName;
		iteratorName = "arsd_foreach_loop_counter_"d ~ to!dstring(++foreachLoopCounter);
		dstring temporaryName = "arsd_foreach_loop_temporary_"d ~ to!dstring(++foreachLoopCounter);

		auto writer = appender!dstring();

		formattedWrite(writer, "
			var %2$s = %5$s;
			if(%2$s != null)
			for(var %1$s = 0; %1$s < %2$s.length; %1$s++) {
				var %3$s = %2$s[%1$s];
				%4$s
		}"d, iteratorName, temporaryName, variableName, insideCode, arrayName);

		auto code = writer.data;

		return to!dstring(code);
	}
}

string beautifyCss(string css) {
	css = css.replace(":", ": ");
	css = css.replace(":  ", ": ");
	css = css.replace("{", " {\n\t");
	css = css.replace(";", ";\n\t");
	css = css.replace("\t}", "}\n\n");
	return css.strip;
}

int fromHex(string s) {
	int result = 0;

	int exp = 1;
	foreach(c; retro(s)) {
		if(c >= 'A' && c <= 'F')
			result += exp * (c - 'A' + 10);
		else if(c >= 'a' && c <= 'f')
			result += exp * (c - 'a' + 10);
		else if(c >= '0' && c <= '9')
			result += exp * (c - '0');
		else
			throw new Exception("invalid hex character: " ~ cast(char) c);

		exp *= 16;
	}

	return result;
}

Color readCssColor(string cssColor) {
	cssColor = cssColor.strip().toLower();

	if(cssColor.startsWith("#")) {
		cssColor = cssColor[1 .. $];
		if(cssColor.length == 3) {
			cssColor = "" ~ cssColor[0] ~ cssColor[0]
					~ cssColor[1] ~ cssColor[1]
					~ cssColor[2] ~ cssColor[2];
		}
		
		if(cssColor.length == 6)
			cssColor ~= "ff";

		/* my extension is to do alpha */
		if(cssColor.length == 8) {
			return Color(
				fromHex(cssColor[0 .. 2]),
				fromHex(cssColor[2 .. 4]),
				fromHex(cssColor[4 .. 6]),
				fromHex(cssColor[6 .. 8]));
		} else
			throw new Exception("invalid color " ~ cssColor);
	} else if(cssColor.startsWith("rgba")) {
		assert(0); // FIXME: implement
		/*
		cssColor = cssColor.replace("rgba", "");
		cssColor = cssColor.replace(" ", "");
		cssColor = cssColor.replace("(", "");
		cssColor = cssColor.replace(")", "");

		auto parts = cssColor.split(",");
		*/
	} else if(cssColor.startsWith("rgb")) {
		assert(0); // FIXME: implement
	} else if(cssColor.startsWith("hsl")) {
		assert(0); // FIXME: implement
	} else
		return Color.fromNameString(cssColor);
	/*
	switch(cssColor) {
		default:
			// FIXME let's go ahead and try naked hex for compatibility with my gradient program
			assert(0, "Unknown color: " ~ cssColor);
	}
	*/
}

/*
Copyright: Adam D. Ruppe, 2010 - 2014
License:   <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Authors: Adam D. Ruppe, with contributions by Nick Sabalausky and Trass3r

        Copyright Adam D. Ruppe 2010-2014.
Distributed under the Boost Software License, Version 1.0.
   (See accompanying file LICENSE_1_0.txt or copy at
        http://www.boost.org/LICENSE_1_0.txt)
*/
