;; shape.inc - the Shape "interface".
;;
;; There is no Shape class. There is no Shape struct, no Shape code, and
;; nothing in any object identifies itself as a Shape. There is only an
;; agreement about what lives at which slot of a vtable:
;;
;;      vtable[0]  Class*          (VT_CLASS, from object.inc)
;;      vtable[1]  long area(this)                       centi-units
;;      vtable[2]  long perimeter(this)                  centi-units
;;      vtable[3]  void show(this)
;;
;; Any object whose vptr points at a table shaped like this can be used as a
;; Shape. That is what an interface *is*: a promise about slot numbers.
;;
;; Slot numbers are ABI. Insert a method in the middle of this list and every
;; separately assembled class becomes silently wrong - which is exactly why
;; C++ ABIs freeze vtable layout, and why adding a virtual function to a
;; published base class breaks binary compatibility.

%ifndef SHAPE_INC
%define SHAPE_INC

%define SHAPE_AREA      0
%define SHAPE_PERIMETER 1
%define SHAPE_SHOW      2
%define SHAPE_SLOTS     3

%endif ; SHAPE_INC
