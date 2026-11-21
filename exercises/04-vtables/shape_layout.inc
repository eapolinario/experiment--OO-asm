;; shape_layout.inc - concrete object layouts for the Shape implementations.

%ifndef SHAPE_LAYOUT_INC
%define SHAPE_LAYOUT_INC

struc Circle
    .vptr:      resq 1                  ; MUST be first: the object model says so
    .r:         resq 1
endstruc

struc Rect
    .vptr:      resq 1
    .w:         resq 1
    .h:         resq 1
endstruc

%endif ; SHAPE_LAYOUT_INC
