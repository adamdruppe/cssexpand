import std.file;
import std.stdio;
import std.array;
import arsd.html;

void main(string[] args) {
	if(args.length <= 1) {
		writeln("Missing arguments, pass all your css files to cssexpand.\ne.g.: cssexpand styles/*.css > final.css");
		return;
	}

	string source;

	foreach(arg; args[1 .. $]) {
		source ~= readText(arg);
	}

	// Let $ be used instead of ¤ in the source
	// while still allowing __DOLLAR__ to be used as the
	// literally CSS thing
	source = source.replace("$", "¤");
	source = source.replace("__DOLLAR__", "$");

	auto me = new CssMacroExpander();
	std.stdio.write(me.expandAndDenest(source));
}
