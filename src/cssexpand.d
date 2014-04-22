import std.file;
import std.stdio;
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

	auto me = new CssMacroExpander();
	std.stdio.write(me.expandAndDenest(source));
}
