/** Deterministic source generator for the C0 corpus; no compiler logic. */
const encoder = new TextEncoder();
export const FIXTURE_DIR = new URL("../fixtures/weather/", import.meta.url);
export const PART_NAMES = ["DATA01.SK8", "GROUPS.SK8", "REPORTS.SK8"] as const;
export const DATA_COUNT = 224;
export const GROUP_SIZE = 16;
export const GLOBAL_COUNT = 256;

export interface CorpusFiles {
  readonly manifest: Uint8Array;
  readonly parts: ReadonlyMap<string, Uint8Array>;
}

export interface ExpectedResults {
  readonly count: number;
  readonly totalRain: number;
  readonly totalHigh: number;
  readonly hotDays: number;
  readonly wetDays: number;
  readonly hotHeavyRain: number;
  readonly firstDay: number;
  readonly firstLow: number;
  readonly counterResult: number;
  readonly outputs: Readonly<Record<"r" | "R" | "h" | "other", string>>;
}

export function dailyName(day: number): string {
  return `daily-sample-${String(day).padStart(3, "0")}`;
}

function dataRows(): readonly [number, number, number, number][] {
  return Array.from({ length: DATA_COUNT }, (_, index) => {
    const day = index + 1;
    const low = (day % 17) - 8;
    return [day, low, low + 12 + (day % 5), day % 20];
  });
}

function dataSource(): string {
  return dataRows().map(([day, low, high, rain]) =>
    `(define ${dailyName(day)} '(${day} ${low} ${high} ${rain}))\n`
  ).join("");
}

function groupSource(): string {
  return Array.from({ length: DATA_COUNT / GROUP_SIZE }, (_, index) => {
    const first = index * GROUP_SIZE + 1;
    const names = Array.from(
      { length: GROUP_SIZE },
      (_, offset) => dailyName(first + offset),
    ).join(" ");
    return `(define sample-group-${String(index + 1).padStart(2, "0")}\n` +
      `  (list ${names}))\n`;
  }).join("");
}

function reportSource(): string {
  return [
    `(define append-list
  (lambda (left right)
    (if (null? left)
        right
        (cons (car left)
              (append-list (cdr left) right)))))`,
    `(define join-chunks
  (lambda (chunks)
    (fold-left append-list '() chunks)))`,
    `(define fold-left
  (lambda (proc seed items)
    (if (null? items)
        seed
        (fold-left proc (proc seed (car items)) (cdr items)))))`,
    `(define all-samples
  (join-chunks
    (list ${
      Array.from({ length: 14 }, (_, index) =>
        `sample-group-${String(index + 1).padStart(2, "0")}`).join(" ")
    })))`,
    `(define sample-day (lambda (sample) (car sample)))`,
    `(define sample-low (lambda (sample) (car (cdr sample))))`,
    `(define sample-high (lambda (sample) (car (cdr (cdr sample)))))`,
    `(define sample-rain (lambda (sample) (car (cdr (cdr (cdr sample))))))`,
    `(define sum-rain
  (lambda (samples)
    (fold-left
      (lambda (total sample) (+ total (sample-rain sample)))
      0 samples)))`,
    `(define sum-high
  (lambda (samples)
    (fold-left
      (lambda (total sample) (+ total (sample-high sample)))
      0 samples)))`,
    `(define count-hot
  (lambda (samples)
    (fold-left
      (lambda (total sample)
        (if (> (sample-high sample) 20) (+ total 1) total))
      0 samples)))`,
    `(define count-wet
  (lambda (samples)
    (fold-left
      (lambda (total sample)
        (if (> (sample-rain sample) 0) (+ total 1) total))
      0 samples)))`,
    `(define make-counter
  (lambda ()
    (let ((cell 0))
      (list
        (lambda ()
          (begin (set! cell (+ cell 1)) cell))
        (lambda () cell)))))`,
    `(define even-count?
  (lambda (count)
    (if (= count 0)
        #t
        (odd-count? (- count 1)))))`,
    `(define odd-count?
  (lambda (count)
    (if (= count 0)
        #f
        (even-count? (- count 1)))))`,
    `(define late-shadow
  (letrec ((origin (lambda () 11)))
    (let ((answer (origin)))
      (lambda ()
        (define probe (lambda () answer))
        (define answer 37)
        (probe)))))`,
    `(define scan-report
  (lambda (samples)
    (let* ((first (car samples))
           (first-day (sample-day first))
           (first-low (sample-low first))
           (total-rain (sum-rain samples))
           (total-high (sum-high samples))
           (hot (count-hot samples))
           (wet (count-wet samples))
           (counter (make-counter))
           (next (car counter))
           (read (car (cdr counter))))
      (let scan ((rest samples) (seen 0) (hot-heavy-rain 0))
        (if (null? rest)
            (list seen total-rain total-high hot wet
                  first-day first-low (read) hot-heavy-rain)
            (let* ((sample (car rest))
                   (high (sample-high sample))
                   (rain (sample-rain sample)))
              (begin
                (next)
                (scan (cdr rest) (+ seen 1)
                      (if (and (> high 20) (> rain 10))
                          (+ hot-heavy-rain 1)
                          hot-heavy-rain)))))))))`,
    `(define run-report
  (lambda ()
    (let ((input (read-char)))
      (begin
        (cond
          ((or (eq? input #\\r) (eq? input #\\R))
           (write (sum-rain all-samples)))
          ((eq? input #\\h) (write (count-hot all-samples)))
          (else (write (scan-report all-samples))))
        (newline)
        (write (late-shadow))
        (newline)
        (write (even-count? 30000))
        (newline)))))`,
    `(run-report)`,
  ].join("\n") + "\n";
}

export function buildCorpus(): CorpusFiles {
  const parts = new Map<string, Uint8Array>([
    ["DATA01.SK8", encoder.encode(dataSource())],
    ["GROUPS.SK8", encoder.encode(groupSource())],
    ["REPORTS.SK8", encoder.encode(reportSource())],
  ]);
  const manifest = encoder.encode(`${PART_NAMES.join("\n")}\n`);
  return { manifest, parts };
}

export function expectedResults(): ExpectedResults {
  const rows = dataRows();
  const totalRain = rows.reduce((sum, row) => sum + row[3], 0);
  const totalHigh = rows.reduce((sum, row) => sum + row[2], 0);
  const hotDays = rows.filter((row) => row[2] > 20).length;
  const wetDays = rows.filter((row) => row[3] > 0).length;
  const hotHeavyRain = rows.filter((row) => row[2] > 20 && row[3] > 10).length;
  const summary =
    `(${rows.length} ${totalRain} ${totalHigh} ${hotDays} ${wetDays} ` +
    `${rows[0]![0]} ${rows[0]![1]} ${rows.length} ${hotHeavyRain})`;
  return {
    count: rows.length,
    totalRain,
    totalHigh,
    hotDays,
    wetDays,
    hotHeavyRain,
    firstDay: rows[0]![0],
    firstLow: rows[0]![1],
    counterResult: rows.length,
    outputs: {
      r: `${totalRain}\r\n37\r\n#t\r\n`,
      R: `${totalRain}\r\n37\r\n#t\r\n`,
      h: `${hotDays}\r\n37\r\n#t\r\n`,
      other: `${summary}\r\n37\r\n#t\r\n`,
    },
  };
}
