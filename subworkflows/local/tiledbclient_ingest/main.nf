include { TILEDBCLIENT_INGEST } from '../../../modules/local/tiledbclient/ingest/main'

process TILEDBCLIENT_COLLECT_VCFS {
    label 'process_low'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'docker.io/tiledbenterprise/carrara-udf-genomics-py312:0.2.0' :
        'docker.io/tiledbenterprise/carrara-udf-genomics-py312:0.2.0' }"

    input:
    val(vcf_paths)
    val(tiledb_dataset_name)

    output:
    val(sample_list_uri), emit: sample_list_uri
    path "versions.yml",  emit: versions

    script:
    def sorted_paths = vcf_paths.sort().join('\n')
    def dataset_base = tiledb_dataset_name.replaceAll('/+$', '')
    sample_list_uri = "${dataset_base}/sample_list.txt"
    """
    cat <<'PATHS' | sort > sample_list.txt
${sorted_paths}
PATHS

    python3 <<EOF
import tiledb

uri = '${sample_list_uri}'
with open('sample_list.txt', 'r') as f:
    content = f.read()

vfs = tiledb.VFS()
with vfs.open(uri, 'wb') as fh:
    fh.write(content.encode('utf-8'))

print(f"Uploaded sample list to {uri}")
EOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version 2>&1 | sed 's/Python //')
        tiledb: \$(python3 -c "import tiledb; print(tiledb.version())" 2>&1)
    END_VERSIONS
    """
}

workflow TILEDBCLIENT_INGEST_VCF {
    take:
    vcf_ch            // channel: [ val(meta), path(vcf) ]
    tiledb_dataset_name

    main:
    ch_versions = Channel.empty()

    // Collect all VCF paths into a single list
    vcf_paths = vcf_ch.map { meta, vcf -> vcf.toString() }.collect()

    TILEDBCLIENT_COLLECT_VCFS(vcf_paths, tiledb_dataset_name)

    ch_versions = ch_versions.mix(TILEDBCLIENT_COLLECT_VCFS.out.versions)

    TILEDBCLIENT_INGEST(
        TILEDBCLIENT_COLLECT_VCFS.out.sample_list_uri,
        tiledb_dataset_name,
        params.tiledb_acn
    )

    ch_versions = ch_versions.mix(TILEDBCLIENT_INGEST.out.versions)

    emit:
    versions = ch_versions // channel: [ versions.yml ]
}
