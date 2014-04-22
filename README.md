cssexpand
=========

A css expander tool made with my html.d. It uses the expandAndDenest function of html.d's MacroExpander.

Features
========

CSS comments are stripped out.

Nested CSS rules are expanded. e.g. .foo { .bar { content } } is expanded into .foo .bar { content }.

Nested items that start with a \& or : are attached without a space: .foo { :first-child { ... }} becomes .foo:first-child { ... }.

color.d's color functions are available as macros (see below).

Macros are expanded and can be user-defined. They are initiated with the ¤ character. You might modify the source (cssexpand.d) to add a call to std.array.replace to change some other character into this if you find it hard to type. (On my editor, I set F7 to output ¤ to make it easy to use.)

You can define new macros with ¤define(name, [args...]) { contents } and set values with ¤set(name, value);

Then you use the macros with ¤name(args...);

Tip: the final arg to a macro can always be given as a {} block. See the demo file for an example.

All sets are done before any expansion is done. So you can define a file later that sets a value that is used earlier.

Color macros
============

makeTextColor: given a color, return white or black based on opposite contrast (doesn't do a great job with colors in the middle, notably CSS's green, best to use with pretty extreme but configurable background colors).

oppositeLightness: changes the lightness 180 degrees, leaving hue and saturation unchanged. So white becomes black.

lighten, darken: changes luminance by the given multiplier

moderate, extremify: changes luminance but makes lights darker and darks lighter (or vice versa for extremify)

setLightness, setHue, setSaturation: changes the individual HSL values

rotateHue: changes the hue around the wheel

saturate, desaturate: changes saturation


See color.d's source for details.


tbh I think the nested expanding is the biggest benefit, but the macros can be cool too.
