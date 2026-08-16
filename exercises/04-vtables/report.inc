;; report.inc / report.asm - shared formatting so the classes stay readable.
;;
;; Nothing object-oriented happens here; it exists so that Circle and Rect can
;; print a line without each carrying its own printf boilerplate.

%ifndef REPORT_INC
%define REPORT_INC

; void report_shape(const char *name, const char *dims,
;                   long area_centi, long perimeter_centi)
extern report_shape

%endif ; REPORT_INC
