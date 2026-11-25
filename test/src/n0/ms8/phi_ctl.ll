declare ptr @mk()
declare ptr @mk2()
declare void @safe()

; phi_real: the phi RESULT is live across @safe with no memory home -> must be reported (1 pair: %r across safe)
define void @phi_real(i1 %c) {
entry:
  br i1 %c, label %a, label %b
a:
  %x = call ptr @mk()
  br label %m
b:
  %y = call ptr @mk2()
  br label %m
m:
  %r = phi ptr [ %x, %a ], [ %y, %b ]
  call void @safe()
  store i32 0, ptr %r
  ret void
}

; op_across_in_pred: operand %x is live across @safe in its own predecessor block -> must be reported (1 pair: %x across safe)
define void @op_across_in_pred(i1 %c) {
entry:
  br i1 %c, label %a, label %b
a:
  %x = call ptr @mk()
  call void @safe()
  br label %m
b:
  %y = call ptr @mk2()
  br label %m
m:
  %r = phi ptr [ %x, %a ], [ %y, %b ]
  %s = alloca ptr
  store ptr %r, ptr %s
  ret void
}

; no_cross: operands only flow along their own edge: %x is NOT live across the call in b, %y not across the call in a -> 0 pairs
define void @no_cross(i1 %c) {
entry:
  br i1 %c, label %a, label %b
a:
  %x = call ptr @mk()
  br label %m
b:
  %y = call ptr @mk2()
  br label %m
m:
  %r = phi ptr [ %x, %a ], [ %y, %b ]
  %s = alloca ptr
  store ptr %r, ptr %s
  ret void
}

; loop_phi: loop-carried pointer %p (header phi) is live across @safe in the body -> must be reported (1 pair: %p across safe)
define void @loop_phi(i1 %c) {
entry:
  %init = call ptr @mk()
  br label %hdr
hdr:
  %p = phi ptr [ %init, %entry ], [ %next, %body ]
  br i1 %c, label %body, label %exit
body:
  call void @safe()
  %next = getelementptr i8, ptr %p, i32 8
  br label %hdr
exit:
  store i32 0, ptr %p
  ret void
}

; phi_const: null operand and a pointer operand; %q not live across the call in the null path -> 0 pairs
define void @phi_const(i1 %c) {
entry:
  br i1 %c, label %a, label %b
a:
  %q = call ptr @mk()
  br label %m
b:
  call void @safe()
  br label %m
m:
  %r = phi ptr [ %q, %a ], [ null, %b ]
  %s = alloca ptr
  store ptr %r, ptr %s
  ret void
}
