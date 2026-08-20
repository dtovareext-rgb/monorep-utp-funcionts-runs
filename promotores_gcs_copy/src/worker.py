"""Worker: 1 task = 1 objeto del manifiesto (rewrite GCS→GCS)."""

from __future__ import annotations

from typing import Any

from gcs_copy import dest_exists, rewrite_object, storage_client


def process_one(config: dict[str, Any], item: dict[str, Any]) -> dict[str, Any]:
    src_cfg = config["source"]
    dest_cfg = config["dest"]
    skip_if_exists = bool(config.get("sync", {}).get("skip_if_exists_in_dest", True))

    src_key = item["key"]
    dest_key = item.get("dest_key")
    if not dest_key:
        raise ValueError(f"manifiesto sin dest_key: {src_key}")

    src_client = storage_client(src_cfg["project_id"])
    dst_client = storage_client(dest_cfg["project_id"])
    src_bucket = src_cfg["bucket_name"]
    dst_bucket = dest_cfg["bucket_name"]

    if skip_if_exists and dest_exists(dst_client, dst_bucket, dest_key):
        return {
            "status": "ok",
            "result": "already_in_gcs",
            "src_uri": f"gs://{src_bucket}/{src_key}",
            "dst_uri": f"gs://{dst_bucket}/{dest_key}",
        }

    size = rewrite_object(
        src_client,
        dst_client,
        src_bucket=src_bucket,
        src_key=src_key,
        dst_bucket=dst_bucket,
        dst_key=dest_key,
    )
    return {
        "status": "ok",
        "result": "copied",
        "bytes": size,
        "src_uri": f"gs://{src_bucket}/{src_key}",
        "dst_uri": f"gs://{dst_bucket}/{dest_key}",
    }
