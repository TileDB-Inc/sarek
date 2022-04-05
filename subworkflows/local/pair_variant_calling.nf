//
// PAIRED VARIANT CALLING
//
include { GATK_TUMOR_NORMAL_SOMATIC_VARIANT_CALLING } from '../../subworkflows/nf-core/gatk4/tumor_normal_somatic_variant_calling/main'
include { MSISENSORPRO_MSI_SOMATIC                  } from '../../modules/nf-core/modules/msisensorpro/msi_somatic/main'
include { RUN_CONTROLFREEC                        } from '../nf-core/variantcalling/controlfreec/somatic/main.nf'
include { RUN_MANTA_SOMATIC                         } from '../nf-core/variantcalling/manta/somatic/main.nf'
include { RUN_STRELKA_SOMATIC                       } from '../nf-core/variantcalling/strelka/somatic/main.nf'

workflow PAIR_VARIANT_CALLING {
    take:
        tools
        cram_pair                     // channel: [mandatory] cram
        dbsnp                         // channel: [mandatory] dbsnp
        dbsnp_tbi                     // channel: [mandatory] dbsnp_tbi
        dict                          // channel: [mandatory] dict
        fasta                         // channel: [mandatory] fasta
        fasta_fai                     // channel: [mandatory] fasta_fai
        intervals                     // channel: [mandatory] intervals/target regions
        intervals_bed_gz_tbi          // channel: [mandatory] intervals/target regions index zipped and indexed
        intervals_bed_combined_gz_tbi // channel: [mandatory] intervals/target regions all in one file zipped and indexed
        intervals_bed_combine_gz      // channel: [mandatory] intervals/target regions zipped in one file
        intervals_bed_combined        // channel: [mandatory] intervals/target regions in one file unzipped
        num_intervals                 // val: number of intervals that are used to parallelize exection, either based on capture kit or GATK recommended for WGS
        no_intervals
        msisensorpro_scan             // channel: [optional]  msisensorpro_scan
        germline_resource             // channel: [optional]  germline_resource
        germline_resource_tbi         // channel: [optional]  germline_resource_tbi
        panel_of_normals              // channel: [optional]  panel_of_normals
        panel_of_normals_tbi          // channel: [optional]  panel_of_normals_tbi
        chr_files
        mappability

    main:

    ch_versions          = Channel.empty()

    //TODO: Temporary until the if's can be removed and printing to terminal is prevented with "when" in the modules.config
    manta_vcf            = Channel.empty()
    strelka_vcf          = Channel.empty()
    msisensorpro_output  = Channel.empty()
    mutect2_vcf          = Channel.empty()

    cram_pair_intervals_gz_tbi = cram_pair.combine(intervals_bed_gz_tbi)
        .map{ meta, normal_cram, normal_crai, tumor_cram, tumor_crai, bed, tbi ->
            normal_id = meta.normal_id
            tumor_id = meta.tumor_id

            new_bed = bed.simpleName != "no_intervals" ? bed : []
            new_tbi = tbi.simpleName != "no_intervals" ? tbi : []
            id = bed.simpleName != "no_intervals" ? tumor_id + "_vs_" + normal_id + "_" + bed.simpleName : tumor_id + "_vs_" + normal_id
            new_meta = [ id: id, normal_id: meta.normal_id, tumor_id: meta.tumor_id, gender: meta.gender, patient: meta.patient]
            [new_meta, normal_cram, normal_crai, tumor_cram, tumor_crai, new_bed, new_tbi]
        }

    cram_pair_intervals = cram_pair.combine(intervals)
        .map{ meta, normal_cram, normal_crai, tumor_cram, tumor_crai, intervals ->
            normal_id = meta.normal_id
            tumor_id = meta.tumor_id
            new_intervals = intervals.baseName != "no_intervals" ? intervals : []
            id = new_intervals ? tumor_id + "_vs_" + normal_id + "_" + new_intervals.baseName : tumor_id + "_vs_" + normal_id
            new_meta = [ id: id, normal_id: meta.normal_id, tumor_id: meta.tumor_id, gender: meta.gender, patient: meta.patient ]
            [new_meta, normal_cram, normal_crai, tumor_cram, tumor_crai, intervals]
        }

    if (tools.contains('controlfreec')){
        cram_normal_intervals_no_index = cram_pair_intervals
                    .map {meta, normal_cram, normal_crai, tumor_cram, tumor_crai, intervals ->
                            [meta, normal_cram, intervals]
                        }

        cram_tumor_intervals_no_index = cram_pair_intervals
                    .map {meta, normal_cram, normal_crai, tumor_cram, tumor_crai, intervals ->
                            [meta, tumor_cram, intervals]
                        }

        RUN_CONTROLFREEC(cram_normal_intervals_no_index,
                        cram_tumor_intervals_no_index,
                        fasta,
                        fasta_fai,
                        dbsnp,
                        dbsnp_tbi,
                        chr_files,
                        mappability,
                        intervals_bed_combined,
                        num_intervals)
        ch_versions = ch_versions.mix(RUN_CONTROLFREEC.out.versions)
    }
    if (tools.contains('manta')) {
        RUN_MANTA_SOMATIC(  cram_pair_intervals_gz_tbi,
                            fasta,
                            fasta_fai,
                            intervals_bed_combine_gz,
                            num_intervals)

        manta_vcf                            = RUN_MANTA_SOMATIC.out.manta_vcf
        manta_candidate_small_indels_vcf     = RUN_MANTA_SOMATIC.out.manta_candidate_small_indels_vcf
        manta_candidate_small_indels_vcf_tbi = RUN_MANTA_SOMATIC.out.manta_candidate_small_indels_vcf_tbi
        ch_versions                          = ch_versions.mix(RUN_MANTA_SOMATIC.out.versions)
    }

    if (tools.contains('strelka')) {

        if (tools.contains('manta')) {

            cram_pair_strelka = cram_pair.join(manta_candidate_small_indels_vcf)
                    .join(manta_candidate_small_indels_vcf_tbi)
                    .combine(intervals_bed_gz_tbi)
                    .map{ meta, normal_cram, normal_crai, tumor_cram, tumor_crai, vcf, vcf_tbi, bed, bed_tbi ->
                        normal_id = meta.normal_id
                        tumor_id = meta.tumor_id

                        new_bed = bed.simpleName != "no_intervals" ? bed : []
                        new_tbi = bed_tbi.simpleName != "no_intervals" ? bed_tbi : []
                        id = bed.simpleName != "no_intervals" ? tumor_id + "_vs_" + normal_id + "_" + bed.simpleName : tumor_id + "_vs_" + normal_id
                        new_meta = [ id: id, normal_id: meta.normal_id, tumor_id: meta.tumor_id, gender: meta.gender, patient: meta.patient]
                        [new_meta, normal_cram, normal_crai, tumor_cram, tumor_crai, vcf, vcf_tbi, new_bed, new_tbi]
                    }
        } else {
            cram_pair_strelka = cram_pair_intervals_gz_tbi.map{
                    meta, normal_cram, normal_crai, tumor_cram, tumor_crai, bed, tbi ->
                    [meta, normal_cram, normal_crai, tumor_cram, tumor_crai, [], [], bed, tbi]
            }
        }

        RUN_STRELKA_SOMATIC(cram_pair_strelka,
                            fasta,
                            fasta_fai,
                            intervals_bed_combine_gz,
                            num_intervals)

        strelka_vcf = RUN_STRELKA_SOMATIC.out.strelka_vcf
        ch_versions = ch_versions.mix(RUN_STRELKA_SOMATIC.out.versions)
    }

    if (tools.contains('msisensorpro')) {

        cram_pair_msisensor = cram_pair.combine(intervals_bed_combined)
        MSISENSORPRO_MSI_SOMATIC(cram_pair_msisensor, fasta, msisensorpro_scan)
        ch_versions = ch_versions.mix(MSISENSORPRO_MSI_SOMATIC.out.versions)
        msisensorpro_output = msisensorpro_output.mix(MSISENSORPRO_MSI_SOMATIC.out.output_report)
    }

    if (tools.contains('mutect2')) {
        cram_pair_intervals.map{ meta, normal_cram, normal_crai, tumor_cram, tumor_crai, intervals ->
                [meta, [normal_cram, tumor_cram], [normal_crai, tumor_crai], intervals, ['normal']]
                }.set{cram_pair_mutect2}

        GATK_TUMOR_NORMAL_SOMATIC_VARIANT_CALLING(
            cram_pair_mutect2,
            fasta,
            fasta_fai,
            dict,
            germline_resource,
            germline_resource_tbi,
            panel_of_normals,
            panel_of_normals_tbi,
            intervals_bed_combine_gz,
            num_intervals
        )

        mutect2_vcf = GATK_TUMOR_NORMAL_SOMATIC_VARIANT_CALLING.out.mutect2_vcf
        ch_versions = ch_versions.mix(GATK_TUMOR_NORMAL_SOMATIC_VARIANT_CALLING.out.versions)
    }

    // if (tools.contains('tiddit')) {
    // }

    emit:
    manta_vcf
    msisensorpro_output
    mutect2_vcf
    strelka_vcf
    versions    = ch_versions
}
