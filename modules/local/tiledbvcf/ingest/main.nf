process TILEDBVCF_INGEST {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'docker.io/tiledbenterprise/carrara-udf-genomics-py312:0.2.0' :
        'docker.io/tiledbenterprise/carrara-udf-genomics-py312:0.2.0' }"

    input:
    tuple val(meta), path(vcf_file)
    tuple val(meta), path(tbi_file)
    val(tiledb_db)

    output:
    path "versions.yml"           , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    """
    tiledbvcf store --uri ${tiledb_db} ${args} ${vcf_file}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        tiledbvcf: \$(tiledbvcf --version 2>&1 | grep TileDB-VCF |sed 's/^.*version //;')
    END_VERSIONS
    """
}
