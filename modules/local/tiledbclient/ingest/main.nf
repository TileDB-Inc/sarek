process TILEDBCLIENT_INGEST {
    label 'process_low'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'docker.io/tiledbenterprise/carrara-udf-genomics-py312:0.2.0' :
        'docker.io/tiledbenterprise/carrara-udf-genomics-py312:0.2.0' }"

    input:
    val(sample_list_uri)
    val(dataset_uri)
    val(acn)

    output:
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def acn_arg = acn ? "acn='${acn}'," : ''
    """
    python3 <<EOF
import tiledb.client

dag = tiledb.client.vcf.ingest(
    dataset_uri='${dataset_uri}',
    sample_list_uri='${sample_list_uri}',
    vcf_batch_size=100,
    consolidate_stats=False,
    verbose=True,
    ${acn_arg}
)
EOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version 2>&1 | sed 's/Python //')
        tiledb: \$(python3 -c "import tiledb; print(tiledb.version())" 2>&1)
    END_VERSIONS
    """
}
