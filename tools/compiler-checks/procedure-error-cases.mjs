export const applyRuntimeErrorCases = [
  ["APPSHORT.SK8", "(apply +)", "RUNTIME ERROR\r\n"],
  ["APPBAD.SK8", "(apply + (cons 1 2))", "RUNTIME ERROR\r\n"],
  [
    "APPARITY.SK8",
    "(apply (lambda (x) x) '())",
    "RUNTIME ERROR\r\n",
  ],
  [
    "APPCOUNT.SK8",
    "(apply + (cons 1 (cons 2 (cons 3 (cons 4 (cons 5 (cons 6 (cons 7 (cons 8 (cons 9 '()))))))))))",
    "RUNTIME ERROR\r\n",
  ],
];

export const runtimeErrorCases = [
  ["ARITY.SK8", "((lambda (x) x) 1 2)", "RUNTIME ERROR\r\n"],
  [
    "RSTARITY.SK8",
    "((lambda (first second . rest) first) 1)",
    "RUNTIME ERROR\r\n",
  ],
  ["UNBSET.SK8", "(set! missing 42)", "UNBOUND\r\n"],
  [
    "DEEPREC.SK8",
    "(define f (lambda (n) (if (zero? n) 0 (+ 1 (f (- n 1)))))) (f 200)",
    "RUNTIME ERROR\r\n",
  ],
  [
    "ECSTALE.SK8",
    "(define saved #f) (call/ec (lambda (escape) (set! saved escape) 7)) (saved 1)",
    "RUNTIME ERROR\r\n",
  ],
  [
    "ECARITY.SK8",
    "(call/ec (lambda (escape) (escape)))",
    "RUNTIME ERROR\r\n",
  ],
];

export const vectorRuntimeErrorCases = [
  ["VREFERR.SK8", "(vector-ref (vector 1) 1)", "RUNTIME ERROR\r\n"],
  ["VSETERR.SK8", "(vector-set! (vector 1) 1 2)", "RUNTIME ERROR\r\n"],
  ["VLONGERR.SK8", "(make-vector 65 0)", "RUNTIME ERROR\r\n"],
  ["VTYPEERR.SK8", "(vector-length 1)", "RUNTIME ERROR\r\n"],
  [
    "VLENERR.SK8",
    "(vector-length (vector 1) 2)",
    "RUNTIME ERROR\r\n",
  ],
];
