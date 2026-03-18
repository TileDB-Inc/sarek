process TILEDBVCF_CREATE {
    tag "$meta.id"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'docker.io/tiledbenterprise/carrara-udf-genomics-py312:0.2.0' :
        'docker.io/tiledbenterprise/carrara-udf-genomics-py312:0.2.0' }"

    input:
    tuple val(meta), val(db_name)

    output:
    tuple val(meta), val(db_name), emit: tiledb_db
    path "versions.yml", emit: versions

    when:
    params.tiledb_create_dataset

    script:
    """
    if tiledbvcf stat --uri ${db_name} 2>/dev/null; then
        echo "Dataset already exists. Skipping creation."
    else
        echo "Dataset does not exist. Creating dataset."
        tiledbvcf create --uri ${db_name}
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        tiledbvcf: \$(tiledbvcf --version 2>&1 | sed 's/^.*version //; s/Using.*\$//')
    END_VERSIONS
    """
}
