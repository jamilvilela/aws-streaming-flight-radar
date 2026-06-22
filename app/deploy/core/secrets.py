"""Secrets Manager — manage DMS Aurora credentials secret."""

from __future__ import annotations

import json
from typing import Optional

import boto3

from ..ui import console
from .config import DeployConfig
from .terraform import TerraformRunner


class DMSSecretManager:
    """Manages the DMS Aurora PostgreSQL credentials secret."""

    def __init__(self, config: DeployConfig, tf_runner: TerraformRunner):
        self._config = config
        self._tf_runner = tf_runner
        self._client = boto3.client("secretsmanager", region_name=config.aws_region)

    def ensure_secret(self) -> bool:
        """
        Ensure the DMS secret exists in Secrets Manager.
        Returns True if the secret is ready.
        """
        secret_name = self._config.dms_secret_name
        console.step_header(f"STEP 7.5 — DMS Secret ({secret_name})")

        try:
            response = self._client.describe_secret(SecretId=secret_name)
            # Check if scheduled for deletion
            if response.get("DeletedDate"):
                console.info(f"Secret {secret_name} estava agendado para deleção. Restaurando...")
                self._client.restore_secret(SecretId=secret_name)
                console.ok(f"Secret {secret_name} restaurado")
            else:
                console.ok(f"Secret {secret_name} já existe")
            return True

        except self._client.exceptions.ResourceNotFoundException:
            console.info(f"Criando secret {secret_name}...")
            try:
                self._client.create_secret(
                    Name=secret_name,
                    Description="RDS PostgreSQL credentials for DMS source endpoint (created by deploy script)",
                    SecretString='{"username":"placeholder","password":"placeholder"}',
                )
                console.ok(f"Secret {secret_name} criado")
                return True
            except Exception as e:
                console.fail(f"Erro ao criar secret: {e}")
                return False
        except Exception as e:
            console.fail(f"Erro ao verificar secret: {e}")
            return False

    def populate_with_aurora_credentials(self) -> bool:
        """
        Populate the DMS secret with actual Aurora credentials from Terraform outputs.
        Returns True on success.
        """
        if not self._config.rds_admin_password:
            console.warn(
                "RDS_ADMIN_PASSWORD não definido no .env. "
                "Não foi possível popular o secret do DMS."
            )
            return False

        try:
            username = self._tf_runner.get_output("aurora_admin_username") or "dbadmin"
            endpoint = self._tf_runner.get_output("aurora_endpoint") or ""
            port = self._tf_runner.get_output("aurora_port") or "5432"
            dbname = self._tf_runner.get_output("aurora_db_name") or "flightradar"

            secret_value = json.dumps({
                "username": username,
                "password": self._config.rds_admin_password,
                "host": endpoint,
                "port": int(port),
                "dbname": dbname,
            })

            self._client.put_secret_value(
                SecretId=self._config.dms_secret_name,
                SecretString=secret_value,
            )
            console.ok(
                f"Secret '{self._config.dms_secret_name}' populado "
                f"com credenciais Aurora (host/port/dbname incluídos)"
            )
            return True

        except Exception as e:
            console.fail(f"Erro ao popular secret com credenciais Aurora: {e}")
            return False
