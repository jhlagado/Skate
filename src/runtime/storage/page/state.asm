; Runtime page-domain state and bitmap masks.
; Shared data labels for the page modules.
PAGE_IMG: DW 0                     ; Exact final loaded image end supplied by SCFIN.
PAGE_ORG: DW 0                     ; First aligned page in the low managed extent.
PAGE_LO: DW 0                      ; Number of pages before the high extent.
PAGE_HI: DW 0                      ; Number of pages in the selected high extent.
PAGE_CNT: DW 0                     ; Total virtual pages in both explicit extents.
PAGE_SYS: DW 0                     ; Whole pages reserved for bitmap and directory.
PAGE_CAP: DW 0                     ; Currently free object pages.
PAGE_LEN: DW 0                     ; Bitmap byte extent, including trailing padding.
PAGE_MAP: DW 0                     ; Runtime address of the free-page bitmap.
PAGE_DIR: DW 0                     ; Runtime address of the per-page directory.
PAGE_MIN: DW 0                     ; First page address available to callers.
PAGE_IDX: DW 0                     ; Scratch page index for scans and bit updates.
PAGE_RUN: DW 0                     ; Scratch requested run length.
PAGE_POS: DW 0                     ; Successful run start index for address output.
PAGE_PTR: DW 0                     ; Scratch release address.
PAGE_END: DW 0                     ; Scratch exclusive end for extent checks.
PAGE_OK:  DB 0                     ; Nonzero after a successful page-domain init.
PAGE_BIT:  DB 0                    ; Selected bit mask for the current page.
PAGE_POW: DB 1,2,4,8,16,32,64,128 ; Bit masks for one bitmap byte.
