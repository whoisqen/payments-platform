# lib

`guard.py` refuses an experiment outside stage, during a freeze or with an open incident; `validate_fis.py` checks FIS templates against the documented template keys.
`python3 validate_fis.py ../fis/*.json` prints one line per template and exits 1 on any error.
