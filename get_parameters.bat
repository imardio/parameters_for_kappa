#!/bin/bash

####################################################################################################################
#
# THIS PREPARES THE PARAMETERS FOR THE KAPPA PROGRAM, THEN GENERATES AND EXECUTES KAPPA FOR A BATCH OF FILES
#
# WHAT YOU NEED:
#
#	1) The kappa.cpp program
# 	2) Gaussian output files with frequency calculations. Energies will also be taken from these. 
#
#	Output files must follow the naming scheme: 
#								*_rc.gjf.log > Reactant complex
#								*_ts.gjf.log > Transition state
#								*_pc.gjf.log > Product complex
#
#	ELSE: redefine these labels in the script or rename your output files
#
####################################################################################################################

Home=$PWD

# STEP 0

#clear

if [[ -e "scratch" ]]; then
	echo please manually remove old scratch directory
	exit
else
	echo Creating scratch
fi

mkdir -p $Home/scratch
mkdir -p $Home/scratch/Masses
mkdir -p $Home/scratch/Energies
mkdir -p $Home/scratch/Parameters
mkdir -p $Home/scratch/Freqs
mkdir -p $Home/scratch/ZPVE
mkdir -p $Home/scratch/Parameters/scratch

#mkdir -p BACKUP

#cp *.log BACKUP

###############################################################################################
# STEP 1.1 Extraction of Imaginary Frequencies (printed as radians per second) and number of atoms
###############################################################################################

for a in *ts.gjf.log; do
        name=${a%%.gjf.log}
	grep -m 1 "Frequencies --" $a > "zpve_$name"
        cut -c 16-35 "zpve_${name}" > zpve_new_$name
	sed -e 's/[[:space:]]//g' zpve_new_$name > "zpve_${name}"
	echo "scale=25; $(cat zpve_${name}) * 2 * 29979300000 * 3.1415926535897932384626" | bc -l > $name
        rm zpve_new_$name zpve_$name
	
	mv ${name} $Home/scratch/Freqs

done

echo Frequencies: Done

# This block works fine


#########################################################
# STEP 1.2 Extraction of Reduced Masses (printed in Kilograms)
#########################################################

for a in *ts.gjf.log; do
        name=${a%%.gjf.log}
	grep -m 1 "Red. masses --" $a > "zpve_$name"
        cut -c 16-35 "zpve_${name}" > zpve_new_$name
	sed -e 's/[[:space:]]//g' zpve_new_$name > "zpve_${name}"
	echo "scale=40; $(cat zpve_${name}) * 0.00000000000000000000000000166053904" | bc -l > $name
        rm zpve_new_$name zpve_$name

	mv ${name} $Home/scratch/Masses

	grep -m 1 -h -r  "NAtoms=" $a | head -1 | cut -c 9-16 | tr -d ' ' | grep -Eo '[0-9]{1,5}' > ${name}_atoms

	mv ${name}_atoms $Home/scratch/Masses

done

echo Masses: Done

# This block works fine


#########################################################
# STEP 1.3 Extraction of Electronic Energies (in Hartree)
#########################################################

# Energies calculated with Gaussian, either with implicit solvation or in vacuo.

for a in *.gjf.log; do
	if [[ -e "$a" ]]; then
		name=${a%%.gjf.log}
		grep "SCF Done" $a | tail -1 > "pre_eel_$name"
		cut -c 24-42 "pre_eel_$name" > "$Home/scratch/Energies/$name"
		rm "pre_eel_$name"
	else
		echo No energy available for "$name" >> $Home/log
	fi	

	done

echo Energies: Done

# This block works fine

#########################################################
# STEP 1.4 Extraction of ZPVE (in Hartree)
#########################################################

for a in *.log; do
        name=${a%%.gjf.log}
        grep 'Zero-point correction' $a > "zpve_$name"
        sed -e 's/Zero-point correction//g' zpve_$name > zpve_new_$name
        sed -e 's/\=//g' zpve_new_$name > zpve_$name
        sed -e 's/[[:space:]]//g' zpve_$name > zpve_new_$name
	sed -e 's/(Hartree\/Particle)//g' zpve_new_$name > $Home/scratch/ZPVE/zpve2_$name
	tail -1 $Home/scratch/ZPVE/zpve2_$name > $Home/scratch/ZPVE/zpve_$name
	rm zpve_new_$name zpve_$name
	done

echo ZPVE: Done

# This block works fine

############################################################################
# STEP 1.5 Calculation of activation energies 
############################################################################

# Calculation of activation energy, at the potential energy level

cd $Home/scratch/Energies

for i in *_ts; do
	name=${i%%_ts}		
	echo "scale=25; $(cat ${i}) - $(cat ${name}_rc)" | bc -l > "Eactnozpve_${name}"
	echo "scale=25; $(cat Eactnozpve_${name}) * 2625.5*1000/6.022/10^23" | bc -l > "Eact_nozpve_${name}"
	rm "Eactnozpve_$name"
done

#	echo "Eact      =" $(cat Eact_nozpve_${name})

# Calculation of ZPVE-corrected energies

for i in *_ts *_pc *_rc; do
	echo "scale=25; $(cat ${i}) + $(cat $Home/scratch/ZPVE/zpve_${i})" | bc -l > "eel_zpve_${i}"

done

# Calculation of activation energy, corrected by ZPVE

for i in eel_zpve_*_ts; do
	name=${i%%_ts}		
	echo "scale=25; $(cat ${i}) - $(cat ${name}_rc)" | bc -l > "Eactzpve_${name}"
	echo "scale=25; $(cat Eactzpve_${name}) * 2625.5*1000/6.022/10^23" | bc -l > "Eact_${name}"
	rm "Eactzpve_$name"

done

#	echo "Eact ZPVE =" $(cat Eact_${name})

echo Energy differences: Done

# This block works fine

############################################################################
# STEP 2.1 Calculation of parameters for the Kappa program 
############################################################################

##### Calculation of a (DE of reaction with ZPVE) and A (DE of reaction without ZPVE) factors

for i in *_rc; do
	if [[ $i == eel_zpve_* ]]; then
		name=${i%%_rc}
		name2=${name##eel_zpve_}
		echo "$(cat ${name}_pc) - $(cat ${i})" | bc -l > "aa_${name}"

		if (( $(echo "scale=25; $(cat aa_${name}) > 0" |bc -l) )); then
			echo "scale=25; $(cat aa_${name}) * -1" | bc -l > "aaa_${name}"
			echo Reaction with $name is endergonic: "A and a" parameters will be reversed
			mv aaa_${name} aa_${name}
		else
			:
		fi

		echo "scale=25; $(cat aa_${name}) * 2625.5*1000/6.022/10^23" | bc -l > "$Home/scratch/Parameters/a_${name2}"
#		rm "aa_$name"
		
	elif  [[ "$i" != eel_zpve_* ]]; then
		name1=${i%%_rc}
		echo "$(cat ${name1}_pc) - $(cat ${i})" | bc -l > "AA_${name1}"

		if (( $(echo "scale=25; $(cat AA_${name1}) > 0" |bc -l) )); then
			echo "scale=25; $(cat AA_${name1}) * -1" | bc -l > "AAA_${name1}"
			mv AAA_${name1} AA_${name1}
		else
			:
		fi


		echo "scale=25; $(cat AA_${name1}) * 2625.5*1000/6.022/10^23" | bc -l > "$Home/scratch/Parameters/A_${name1}"
#		rm "AA_$name1"
	fi
done

## A and a VALUES ARE DOUBLE-CHECKED AND CORRECT!

echo Parameters 'a' and 'A': Done

##### Calculation of b and B factors

cd $Home/scratch/Parameters/

for i in A_*; do
	name=${i##A_}
	echo "scale=25; $(cat $Home/scratch/Energies/Eact_nozpve_${name}) * 2" | bc -l > "2Eactnozpve_${name}"
	echo "scale=25; $(cat 2Eactnozpve_${name}) - $(cat ${i})"| bc -l > "Arg1_${name}"
	echo "scale=25; $(cat $Home/scratch/Energies/Eact_nozpve_${name}) - $(cat ${i})"| bc -l > "EA_${name}"
	echo "scale=45; $(cat $Home/scratch/Energies/Eact_nozpve_${name}) * $(cat EA_${name})" | bc -l > "EEA_${name}"
	a=$(cat EEA_${name})
	echo "scale=25; 2 * sqrt($a)" | bc -l > "Arg2_${name}"
	echo "scale=25; $(cat Arg1_${name}) + $(cat Arg2_${name})" | bc -l > "B_${name}"
done

# B and b VALUES ARE DOUBLE-CHECKED AND CORRECT!

for i in a_*; do
	name=${i##a_}
	echo "scale=25; $(cat $Home/scratch/Energies/Eact_eel_zpve_${name}) * 2" | bc -l > "$Home/scratch/Energies/2Eactel_${name}"
	echo "scale=25; $(cat $Home/scratch/Energies/2Eactel_${name}) - $(cat ${i})"| bc -l > "arg1_${name}"
	echo "scale=25; $(cat $Home/scratch/Energies/Eact_eel_zpve_${name}) - $(cat ${i})"| bc -l > "Ea_${name}"
	echo "scale=45; $(cat $Home/scratch/Energies/Eact_eel_zpve_${name}) * $(cat Ea_${name})" | bc -l > "EEa_${name}"
	a=$(cat EEa_${name})
	echo "scale=25; 2 * sqrt($a)" | bc -l > "arg2_${name}"
	echo "scale=25; $(cat arg1_${name}) + $(cat arg2_${name})" | bc -l > "b_${name}"
done

echo Parameters 'b' and 'B': Done

#	echo b = $(cat b_${name})
#	echo B = $(cat B_${name})

##### Calculation of Alpha factor

for i in a_*; do
	name=${i##a_}
	echo "scale=25; $(cat $Home/scratch/Masses/${name}_ts) * $(cat $Home/scratch/Freqs/${name}_ts) * $(cat $Home/scratch/Freqs/${name}_ts) * $(cat B_${name})" | bc -l > "alpha2a_${name}"
	echo "scale=45; $(cat $Home/scratch/Energies/Eact_nozpve_$name) * 2 * $(cat EA_${name})" | bc -l > "alpha2b_${name}"
	echo "scale=25; $(cat alpha2a_${name}) / $(cat alpha2b_${name})" | bc -l > "alpha2_${name}"
	b=$(cat alpha2_${name})
	echo "scale=25; sqrt($b)" | bc -l > "alpha_${name}"

done

##### Change of notation: from decimals to scientific notation

for k in a_*; do
	name=${k##a_}
	echo "scale=25; $(cat ${k})" | bc -l | awk '{printf "%.5e\n", $1}' > "scratch/a_${name}"
	echo "scale=25; $(cat b_${name})" | bc -l | awk '{printf "%.5e\n", $1}' > "scratch/b_${name}"
	alpha="$(cat alpha_${name})"
	echo "$alpha" > "scratch/alpha_${name}"
	echo "scale=25; $(cat $Home/scratch/Masses/${name}_ts)" | bc -l | awk '{printf "%.5e\n", $1}' > "$Home/scratch/Parameters/scratch/mu_${name}"

done

# This block works fine

###################
# STEP 3 Generation of a readable output with data that will be fed to the Kappa program 
###################

touch $Home/parameters

data=$Home/parameters

for k in a_*; do
	name=${k##a_}
	echo $name >> $data
	echo " " >> $data
	echo "a	$(cat $Home/scratch/Parameters/scratch/a_${name})" >> $data
	echo "b	$(cat $Home/scratch/Parameters/scratch/b_${name})" >> $data
	echo "Alpha	$(cat $Home/scratch/Parameters/scratch/alpha_${name})" >> $data
	echo "Mu	$(cat $Home/scratch/Parameters/scratch/mu_${name})" >> $data
	echo " " >> $data
done

touch $Home/list

for k in a_*; do
	name=${k##a_}
	echo $name >> $Home/list
done

cd $Home

#rm $Home/scratch

#### Now we will invoke, fill and execute the kappa.cpp program

##########################################################################
##########################################################################
##
##          K     K        A        P P P      P P P        A
##          K   K         A A       P     P    P     P     A A
##          K K	         A   A      P P P      P P P      A   A
##          K   K       A A A A     P          P         A A A A
##          K     K    A       A    P          P        A       A
##
##########################################################################
########## The actual kappa program, Written by Radek Fucik ##############
##########################################################################

work=$Home/scratch/kappa
mkdir $work

echo Entering Kappa calculation

for name in $(cat list); do
	
	cp kappa.cpp $work/kappa_${name}.cpp

#Substitution of the AAAAA string by parameter a

	var_a=$(< $Home/scratch/Parameters/scratch/a_${name}) 
	sed -i -e "s/AAAAA/$var_a/" $work/kappa_$name.cpp

#Substitution of the BBBBB string by parameter b

	var_b=$(< $Home/scratch/Parameters/scratch/b_${name})
	sed -i -e "s/BBBBB/$var_b/" $work/kappa_$name.cpp

#Substitution of the LLLLL string by parameter alpha

	var_l=$(< $Home/scratch/Parameters/scratch/alpha_${name})
	sed -i -e "s/LLLLL/$var_l/" $work/kappa_$name.cpp
	
#Substitution of the MMMMM string by reduced mass

	var_m=$(< $Home/scratch/Parameters/scratch/mu_${name})
	sed -i -e "s/MMMMM/$var_m/" $work/kappa_$name.cpp

# creation of the kappa programs and printing of transmission coefficients into kappa_coeff file

	gcc $work/kappa_$name.cpp -lm -lgsl -lgslcblas -lblas -o $work/kappa_$name
	touch $Home/kappa_coeff
	$work/kappa_$name >> $Home/kappa_coeff

done

echo Kappa: Done
 
exit
	

