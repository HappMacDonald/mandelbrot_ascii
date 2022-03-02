# mandelbrot_ascii
An vt100 compatible UI for exploring the Mandelbrot set, also a vehicle for the author to more fully explore x64 SIMD ASM.

This is also the sister/pilot project to https://github.com/HappMacDonald/MasterBlaster
What I learn here will help better inform how to continue building out the SIMD-focused assembly compiler for my new coding language.

# Command line arguments:
./mandelbrot_ascii.pl [X center of view] [Y center of view] [Height of view screen] [Number of maximum iterations]

Upon quitting, the application will try to output the settings last viewed to STDOUT, so that one can easily browse back to that location by feeding them back in as CLI arguments.

Application will try to suit whatever screen size your terminal is currently in.
If you resize your terminal window, unfortuantely as of this writing it will not notice the change until you perform the next draw command. But then it will.

# Keyboard Control legend:
* UP, DOWN, LEFT, RIGHT arrow keys: pan view port ~33% of its current height or width in any direction
    (defaults to -0.5,0)

* + / -:  zoom in or out by 50%
    (viewport height defaults to 4 units)

* [ / ]: Decrease / Increase maximum number of iterations by a factor of 4
    (maximum iterations defaults to 100)

* q: quit

* CTRL-C: quit, even in the middle of drawing a frame. App will still try to print out current coordinate settings though.

# Mouse control legend (yay mouse support!):
* left click: zoom in around the clicked region by 50%

* right click: pan to center around the clicked region without zooming

* Scrollwheel up/down: zoom in or out by 500% centered on where the mouse was when you scrolled.

* Scrollwheel click/middle click: 1000% zoom around where you clicked

# Credits
Written by Jesse Thompson, aka Happ MacDonald, and all source code offered for public consumption per the Creative Commons Zero v1.0 Universal licence.
