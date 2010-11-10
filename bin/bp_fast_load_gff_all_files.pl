#!/bin/bash

for file in `ls ./`
	do
		bp_fast_load_gff.pl --database 'maize-QuantDisplay' --mach coe.science.oregonstate.local --user maize_gb_admin --password Zeamays --local $file
	done
