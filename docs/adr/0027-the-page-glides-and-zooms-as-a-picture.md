# 27. The page glides, and zooms as a picture until it stops

**Status:** accepted; revises how ADR 21's page follows a zoom

## Context

Scrolling and zooming felt poor, on Windows most of all:

* A mouse wheel's notch moved the page at once, in one frame: 20 pixels a
  line, three lines a notch on Windows, so 67 to 100 pixels at a time — the
  page jumped rather than moved, and Ctrl with the wheel zoomed in jumps of
  a tenth.
* Every change of zoom built the page's layers again: every text box,
  formula and PDF page in view was built and laid out again at every frame
  of a pinch, and each PDF page asked for a new resolution as it went.
* Scrolling on built them all again each time the view moved a quarter of
  its size on, so a scroll caught every few hundred pixels.
* A touchpad scroll went up to two and a half times as far as the fingers
  as they sped up, so the page slid under them instead of following.

## Decision

**A wheel's notch glides.** A scroll of 20 pixels or more is a notch, and
the view goes to where it sends it over the next frames, most of the way in
the first ones and all of it within a tenth of a second
(`CanvasMotion.glide`); notches in quick succession add up. A scroll shorter
than that — a touchpad posing as a wheel, a wheel that turns freely — is
followed at once, being as smooth as it can be. Ctrl with the wheel glides
through its zoom likewise, about the pointer (`CanvasMotion.glideZoom`).

**While the view is zoomed, the page is a picture of itself.** The canvas
knows when the view is being zoomed — fingers pinching a screen or a
touchpad, a wheel's zoom gliding — and says so to the page's layers
(`zooming`). Meanwhile they are only scaled, by the one transform they are
shown through, and built again only where zooming out uncovers what was not
laid out. Once the zoom has stopped they are built once for it, and what is
drawn in pixels, PDF pages, is drawn sharp for it (`CanvasScope.zoomOf` is
the zoom they were built for). A zoom made at once — Ctrl and =, the
toolbar — lays the page out at once, as before.

**What is placed stays placed.** Built again as the view moves on, the page
gives each element still in view the very widget it had, which the
framework then leaves as it is: only what comes into view is built. Built
again from above — the page changed, or what builds its elements — every
element is built anew.

**The page follows the fingers exactly.** A touchpad scroll moves the page
as far as the fingers move, at any speed, and a quick one coasts on as they
lift (ADR 21's momentum), as scrolling does everywhere else on the desktop.

**Fingers put down stop it.** Coasting, the page stops where fingers catch
it, and stays there as they lift. Only a flick the same way, of 600 pixels a
second or more, sends it on faster still: before, any movement the same way
counted, and fingers settling a pixel as they were put down sent it on at
the speed it had, so that only a scroll the other way stopped it. A touchpad
says nothing of fingers put down that do not move at all (GTK 3, which
Flutter's Linux build uses, has no hold gesture); the smallest movement
stops it.

## Consequences

* A pinch costs a frame of raster work and nothing of building or layout;
  the one layout it does costs what a scroll's does, as it ends.
* Zoomed in, text and ink stay sharp as they are scaled — they are drawn as
  shapes — while a PDF page is shown at the resolution it had until the
  zoom stops.
* An element's widget is kept only while the canvas is not built again; a
  widget reading something the canvas is not rebuilt for would show it
  late. Everything the page editor builds elements from rebuilds the
  canvas.
