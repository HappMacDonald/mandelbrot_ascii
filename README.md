# mandelbrot_ascii
An vt100 compatible UI for exploring the Mandelbrot set, also a vehicle for the author to more fully explore x64 SIMD ASM.

This is also the sister/pilot project to https://github.com/HappMacDonald/MasterBlaster
What I learn here will help better inform how to continue building out the SIMD-focused assembly compiler for my new coding language.

# Command line arguments:
./mandelbrot_ascii.pl [quoted JSON containing one or more of the following fields]
{ "simpleJuliaTilt": 0 renders a Julia set, 1 the M-set, and other values slice between them
, "juliaParameterX": X-coordinate of Julia parameter (unusued when rendering M-set)
, "juliaParameterY":
, "viewPortHeight":
, "viewPortCenterX":
, "viewPortCenterY":
, "maximumIterations":
, "photoMode": if present takes the form width, the letter 'x', then height in pixels. Will not render anything to screen but will render to an image file at the requested resolution and then exit.
, "imageName": only valid in photo mode. Defaults to "image_" followed by an ISO-8601-based timestamp.
}


Upon quitting, the application will try to output the settings last viewed to STDOUT, so that one can easily browse back to that location by feeding them back in as CLI arguments.

Application will try to suit whatever screen size your terminal is currently in.
If you resize your terminal window, it will do its best to redraw to your new size.

# Keyboard Control legend:
* UP, DOWN, LEFT, RIGHT arrow keys: pan view port ~33% of its current height or width in any direction
    (center of screen defaults to -0.5,0)

* \+ / -:  zoom in or out by 50%
    (viewport height defaults to 4 units)

* \[ / ]: Decrease / Increase maximum number of iterations by a factor of 4
    (maximum iterations defaults to 50000)

* q: quit

* CTRL-C: quit, even in the middle of drawing a frame. App will still try to print out current coordinate settings though.

# Mouse control legend (yay mouse support!):
* left click: zoom in around the clicked region by 50%

* right click: pan to center around the clicked region without zooming

* Scrollwheel up/down: zoom in or out by 500% centered on where the mouse was when you scrolled.

* Scrollwheel click/middle click: 1000% zoom around where you clicked

# Credits
Written by Jesse Thompson, aka Happ MacDonald, and all source code offered for public consumption per the Creative Commons Zero v1.0 Universal licence.
