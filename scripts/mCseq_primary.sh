#!/bin/bash
#$ -V
#$ -cwd
#$ -pe threads 1
#$ -l m_mem_free=2G
#$ -l tmp_free=10G
#$ -o mCprimary.log
#$ -j y
#$ -N methylcprimary

usage="
##### qsub MethylC_seq_primary.sh [ref] [samplefile]
##### Script to run Bismark and analyze Whole-Genome bisulfite data
##### It copies the fastq files and send each sample into MethylCseq_bismark_singlesample.sh for mapping and methylation extraction
##### Needs to be followed by the reference to use [ B73_v4 | B73_v5 | TAIR10 ] as argument #1, the file name as argument #2, containing the sample name
##### and details of the location of the original fastq files in the archive and whether they are PE or SE
"

set -e -o pipefail

printf "\n\n"
date
printf "\n"

export threads=$NSLOTS
export limthreads=$((threads/4))
export minthreads=$((threads - 1))

export genome=$1
export samplefile=$2

if [ $# -eq 0 ]; then
  printf "$usage\n"
  exit 1
fi

if [[ "$1" == "help" ]]; then
	printf "$usage\n"
	exit 1
fi

if [ ! -d ./fastq ]; then
 mkdir ./fastq
fi

if [ ! -d ./reports ]; then
 mkdir ./reports
fi

if [ ! -d ./mapped ]; then
 mkdir ./mapped
fi

if [ ! -d ./methylcall ]; then
 mkdir ./methylcall
fi

if [ ! -d ./logs ]; then
 mkdir ./logs
fi

if [ ! -d ./chkpts ]; then
 mkdir ./chkpts
fi

case "$genome" in 
	B73_v4)	ref_dir="/grid/martienssen/home/jcahn/nlsas/Genomes/Zea_mays/B73_v4"
			ref="B73_v4";;
	B73_v5)	ref_dir="/grid/martienssen/home/jcahn/nlsas/Genomes/Zea_mays/B73_v5"
			ref="B73_v5";;
	B73_v5_EMseq)	ref_dir="/grid/martienssen/home/jcahn/nlsas/Genomes/Zea_mays/B73_v5_EMseq"
			ref="B73_v5_EMseq";;
	TAIR10) ref_dir="/grid/martienssen/home/jcahn/nlsas/Genomes/Arabidopsis/Col0"
			ref="TAIR10";;
esac

## To create - if needed - the Bismark bowtie2 index and chrom.sizes file
if [ ! -d ${ref_dir}/Bisulfite_Genome ]; then
	printf "\nBuilding index...\n"
	bismark_genome_preparation --bowtie2 --genomic_composition ${ref_dir}
	printf "\nBuilding index finished!\n"
fi

if [ ! -f ${ref_dir}/chrom.sizes ]; then
	file=$(ls ${ref_dir}/${ref}*fa*)
	fileext=${file##*.}
	if [[ "${fileext}" == "gz" ]]; then
		gzip -dkc ${file} > ${ref_dir}/${ref}.fa
		samtools faidx ${ref_dir}/${ref}.fa
		cut -f1,2 ${ref_dir}/${ref}.fa.fai > ${ref_dir}/chrom.sizes
	elif [[ "${fileext}" == "fa" ]]; then
		samtools faidx ${file}
		cut -f1,2 ${file}.fai > ${ref_dir}/chrom.sizes
	else
		printf "\nNo fasta (.fa*) file found in genome folder\n"
		exit
	fi
fi

tmp1=${samplefile%%_samplefile*}
samplefilename=${tmp1##*/}

rm -f reports/summary_coverage_${samplefilename}.txt
printf "Sample\tTotal_Cytosines\tPercentage_uncovered\tPercentage_covered\tPercentage_covered_min3reads\tAverage_coverage_all\tAverage_coverage_covered\tNon_conversion_rate(Pt/Lambda)\n" > reports/summary_coverage_${samplefilename}.txt

pids=()
while read type sample rep seq folder met paired
do
	pathtofastq="/grid/martienssen/data_nlsas/archive/data/${folder}"
	name="${sample}_${rep}"
	if [ -e chkpts/${name} ]; then
		printf "${name} already processed, gathering coverage stats\n"
		qsub -sync y -N met_${name} -o logs/mCrun_${name}.log mCseq_secondary.sh ${ref_dir} ${name} ${samplefilename} ${met} stats &
		pids+=("$!")
	elif [[ ${paired} == "PE" ]] && [ -s fastq/trimmed_${name}_R1.fastq.gz ]; then
		printf "\nRunning worker script for ${name} with param ${ref_dir} ${name} ${met} trim\n"
		qsub -sync y -N met_${name} -o logs/mCrun_${name}.log mCseq_secondary.sh ${ref_dir} ${name} ${samplefilename} ${met} map &
		pids+=("$!")
	elif [[ ${paired} == "PE" ]]; then
		if [ ! -s fastq/${name}_R1.fastq.gz ]; then
			printf "\nCopying fastq for ${name} (${seq} in ${pathtofastq})\n"
			cp ${pathtofastq}/${seq}*R1*fastq.gz fastq/${name}_R1.fastq.gz
			cp ${pathtofastq}/${seq}*R2*fastq.gz fastq/${name}_R2.fastq.gz
		fi
		printf "\nRunning worker script for ${name} with param ${ref_dir} ${name} ${met} trim\n"
		qsub -sync y -N met_${name} -o logs/mCrun_${name}.log mCseq_secondary.sh ${ref_dir} ${name} ${samplefilename} ${met} trim &
		pids+=("$!")
	else 
		printf "\nIs data PE or SE?\n"
		exit 1
	fi
done < ${samplefile}

printf "Waiting for samples to be processed..\n"
wait ${pids[*]}
printf "All samples have been processed\n"

##############################################################################################################################################################


printf "Script finished!\n"
