; Runtime page-domain state and bitmap masks.
; Shared data labels for the page modules.
SRTPGIMG: DW 0                     ; Exact final loaded image end supplied by SCFIN.
SRTPGBAS: DW 0                     ; First aligned page in the low managed extent.
SRTPGLOW: DW 0                     ; Number of pages before the high extent.
SRTPGHIG: DW 0                     ; Number of pages in the selected high extent.
SRTPGCNT: DW 0                     ; Total virtual pages in both explicit extents.
SRTPGMET: DW 0                     ; Whole pages reserved for bitmap and directory.
SRTPGFRE: DW 0                     ; Currently free object pages.
SRTPGBYT: DW 0                     ; Bitmap byte extent, including trailing padding.
SRTPGBMA: DW 0                     ; Runtime address of the free-page bitmap.
SRTPGDIR: DW 0                     ; Runtime address of the per-page directory.
SRTPGFRB: DW 0                     ; First page address available to callers.
SRTPGIDX: DW 0                     ; Scratch page index for scans and bit updates.
SRTPGREQ: DW 0                     ; Scratch requested run length.
SRTPGSTR: DW 0                     ; Successful run start index for address output.
SRTPGADR: DW 0                     ; Scratch release address.
SRTPGEND: DW 0                     ; Scratch exclusive end for extent checks.
SRTPGOK:  DB 0                     ; Nonzero after a successful page-domain init.
SRTBITM:  DB 0                     ; Selected bit mask for the current page.
SRTGMASK: DB 1,2,4,8,16,32,64,128 ; Bit masks for one bitmap byte.
