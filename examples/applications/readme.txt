SKATE FOR CP/M

Skate is a small Scheme compiler for CP/M. This disk contains the
compiler, its runtime, a text editor and three example programs.
It is a work in progress, not a complete Scheme implementation.

GETTING STARTED

  TYPE README.TXT       Read these instructions.
  TYPE RECEIPT.SK8      Read an example's source.
  EDIT RECEIPT.SK8      Edit the example, then save and exit.
  SKATE RECEIPT.SK8     Compile it.
  RECEIPT              Run the compiled program.

The examples are already compiled, so you can also run RECEIPT, ROUTE
or ACCOUNT immediately. Compiling writes a .COM executable and a .NOB
object file. Keep SKATE.RT on the disk alongside SKATE.COM.

EXAMPLES

RECEIPT.SK8  Itemised shop bill. Change the basket quantities or prices.
            Prices are integer cents; the supplied total is 620.
ROUTE.SK8    Search an adventure map for a path from gate to vault.
            Change the world list to alter rooms and exits.
ACCOUNT.SK8  Two independent account balances held in closures.
            Change the transactions; the supplied combined balance
            is 6650 dollars.

These are editable programs, not interactive applications. This version
has output operations but no keyboard-input operation. The last value
of a program is printed automatically. Source files use CP/M line endings
so both TYPE and EDIT can display them.
