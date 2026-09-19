::  mar/armillary/row: one ledger row, at /accounts/<ship>/ledger/<name>.
::
::    Stored as [%1 row]. Append only, never edited after it is written. A
::    noun passthrough; the shape ladder is +read-row in lib/armillary.
::
|_  n=*
++  grad  %noun
++  grow
  |%
  ++  noun  n
  --
++  grab
  |%
  ++  noun  *
  --
--
