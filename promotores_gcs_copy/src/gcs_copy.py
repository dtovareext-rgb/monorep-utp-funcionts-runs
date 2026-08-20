"""Copia GCS→GCS entre proyectos (rewrite server-side)."""

from __future__ import annotations

from typing import Any

from google.cloud import storage


def storage_client(project_id: str) -> storage.Client:
    return storage.Client(project=project_id)


def list_source_objects(
    src_client: storage.Client,
    bucket: str,
    prefix: str,
    min_size: int,
) -> list[dict[str, Any]]:
    objects: list[dict[str, Any]] = []
    for blob in src_client.list_blobs(bucket, prefix=prefix or ""):
        name = blob.name
        if not name or name.endswith("/"):
            continue
        size = int(blob.size or 0)
        if size < min_size:
            continue
        objects.append(
            {
                "key": name,
                "size": size,
                "file_name": name.rsplit("/", 1)[-1],
                "content_type": blob.content_type,
            }
        )
    objects.sort(key=lambda x: x["key"])
    return objects


def dest_exists(dst_client: storage.Client, bucket: str, object_name: str) -> bool:
    return dst_client.bucket(bucket).blob(object_name).exists()


def rewrite_object(
    src_client: storage.Client,
    dst_client: storage.Client,
    *,
    src_bucket: str,
    src_key: str,
    dst_bucket: str,
    dst_key: str,
) -> int:
    """Copia el objeto sin bajarlo al Job. Retorna bytes del destino."""
    src_blob = src_client.bucket(src_bucket).blob(src_key)
    dst_blob = dst_client.bucket(dst_bucket).blob(dst_key)
    token: str | None = None
    rewritten = 0
    while True:
        token, rewritten, _total = dst_blob.rewrite(src_blob, token=token)
        if not token:
            break
    dst_blob.reload()
    return int(dst_blob.size or rewritten or 0)
