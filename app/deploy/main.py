#!/usr/bin/env python3
"""
Streaming Flight Radar — Deploy & Verification Toolkit
=======================================================

CLI interface for deploying and verifying the full streaming pipeline:
  .env loader → Lambda Layer build → Terraform (init/validate/plan/apply)
  → DMS Secrets Manager → Post-deploy verification → Summary

Usage:
  # Full pipeline
  python -m app.deploy.main

  # Skip Terraform apply (plan only)
  python -m app.deploy.main --skip-apply

  # Skip post-deploy verification
  python -m app.deploy.main --no-verify

  # Selective services
  python -m app.deploy.main --services api_gateway,lambda,kinesis
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Optional

import click

from .core.config import DeployConfig
from .core.layer_builder import LambdaLayerBuilder
from .core.secrets import DMSSecretManager
from .core.terraform import TerraformRunner
from .ui import console
from .verify.api_gateway import APIGatewayVerifier
from .verify.cloudwatch import CloudWatchVerifier
from .verify.dms import DMSVerifier
from .verify.iam import IAMVerifier
from .verify.kinesis import KinesisVerifier
from .verify.kms import KMSVerifier
from .verify.lambda_ import LambdaVerifier
from .verify.sqs import SQSVerifier


# ── CLI ──────────────────────────────────────────────────────────────────

@click.command(
    help="Deploy and verify the Streaming Flight Radar pipeline on AWS.",
    epilog="""
Examples:

  \b
  # Full pipeline
  python -m app.deploy.main

  \b
  # Plan only, no apply
  python -m app.deploy.main --skip-apply

  \b
  # Selective verification after manual deployment
  python -m app.deploy.main --skip-apply --no-verify

  \b
  # Verify only specific services
  python -m app.deploy.main --skip-apply --services lambda,kinesis,dms
    """,
)
@click.option(
    "--skip-apply",
    is_flag=True,
    default=False,
    help="Skip terraform apply (init/validate/plan only).",
)
@click.option(
    "--no-verify",
    is_flag=True,
    default=False,
    help="Skip post-deployment verification checks.",
)
@click.option(
    "--services",
    default="all",
    show_default=True,
    help="Comma-separated list of services to verify (e.g. lambda,kinesis,dms). "
         "Use 'all' for all services.",
)
@click.option(
    "--project-root",
    type=click.Path(exists=True, file_okay=False, path_type=Path),
    default=None,
    help="Project root directory (default: current directory).",
)
def main(
    skip_apply: bool = False,
    no_verify: bool = False,
    services: str = "all",
    project_root: Optional[Path] = None,
) -> None:
    """CLI entry point — orchestrates the full deployment pipeline."""
    exit_code = _run_pipeline(skip_apply, no_verify, services, project_root)
    sys.exit(exit_code)


# ── Pipeline orchestrator ────────────────────────────────────────────────

def _run_pipeline(
    skip_apply: bool,
    no_verify: bool,
    services: str,
    project_root: Optional[Path],
) -> int:
    """Run the full deployment pipeline. Returns exit code (0 = success)."""

    # ── 0. Splash ────────────────────────────────────────────────────
    console.console.print()
    console.console.print(
        "[bold cyan]"
        "╔══════════════════════════════════════════════════════╗\n"
        "║    🚀 Streaming Flight Radar — Deploy Pipeline      ║\n"
        "╚══════════════════════════════════════════════════════╝"
        "[/bold cyan]"
    )
    console.console.print()

    # ── 1. Load config ───────────────────────────────────────────────
    console.section_header("Configuration", "Loading .env, tfvars, and environment")

    service_list = [s.strip().lower() for s in services.split(",")]
    run_all = "all" in service_list

    cfg = DeployConfig.from_env_and_args(
        skip_apply=skip_apply,
        no_verify=no_verify,
        services=service_list if not run_all else ["all"],
        project_root=project_root,
    )

    errors = cfg.validate()
    if errors:
        for err in errors:
            console.fail(err)
        console.display_error(
            "Configuração inválida. Verifique os erros acima.",
            "Certifique-se de que .env e infra/tfvars/terraform.tfvars existem.",
        )
        return 1

    console.ok(f"Projeto detectado: {cfg.project_name}")
    console.ok(f"Região AWS: {cfg.aws_region}")
    console.ok(f"Ambiente: {cfg.environment}")

    # ── Credentials check ─────────────────────────────────────────────
    console.section_header(
        "Credentials Check",
        "Verificando credenciais AWS"
    )
    _check_credentials(cfg)

    # ── 3. Build Lambda Layer ──────────────────────────────────────────
    layer_builder = LambdaLayerBuilder(
        requirements_file=cfg.requirements_file,
        layer_root=cfg.layer_root,
    )
    if not layer_builder.build_if_needed():
        console.fail("Falha ao construir Lambda Layer. Abortando.")
        return 1

    # ── 4. Enter infra directory ──────────────────────────────────────
    console.section_header(
        "Infrastructure Directory",
        f"Acessando {cfg.infra_dir}"
    )
    if not cfg.infra_dir.exists():
        console.fail(f"Diretório {cfg.infra_dir} não encontrado. Execute da raiz do projeto.")
        return 1
    console.ok(f"Diretório atual: {cfg.infra_dir}")

    # ── 5-8. Terraform lifecycle ──────────────────────────────────────
    tf = TerraformRunner(infra_dir=cfg.infra_dir, tfvars_file=cfg.tfvars_file)

    console.section_header(
        "Terraform Pipeline",
        f"init → validate → plan {'→ apply' if not skip_apply else ''}"
    )

    if not tf.init():
        return 2
    if not tf.validate():
        return 2
    if not tf.plan():
        return 2

    if not skip_apply:
        # 7.5 — DMS Secrets Manager
        dms_secret = DMSSecretManager(cfg, tf)
        dms_secret.ensure_secret()

        # 8 — Apply
        if not tf.apply():
            return 2

        # Populate DMS secret with Aurora credentials
        dms_secret.populate_with_aurora_credentials()
    else:
        console.warn("--skip-apply informado; apply não será executado.")

    # ── 9. Terraform outputs ─────────────────────────────────────────
    console.section_header("Terraform Outputs")
    tf.print_all_outputs()

    # ── 10. Post-deploy verification ──────────────────────────────────
    if no_verify:
        console.warn("--no-verify informado; pulando checagens pós-deploy.")
        _print_summary(cfg, tf)
        return 0

    console.section_header(
        "Post-Deploy Verification",
        "Verificando recursos do pipeline"
    )

    missing = False

    if run_all or "kinesis" in service_list:
        if not KinesisVerifier(cfg).verify():
            missing = True

    if run_all or "lambda" in service_list:
        if not LambdaVerifier(cfg).verify():
            missing = True

    if run_all or "iam" in service_list:
        if not IAMVerifier(cfg).verify():
            missing = True

    if run_all or "sqs" in service_list:
        if not SQSVerifier(cfg).verify():
            missing = True

    if run_all or "api_gateway" in service_list:
        if not APIGatewayVerifier(cfg).verify():
            missing = True

    if run_all or "cloudwatch" in service_list:
        if not CloudWatchVerifier(cfg).verify():
            missing = True

    if run_all or "dms" in service_list:
        if not DMSVerifier(cfg).verify():
            missing = True

    if run_all or "kms" in service_list:
        if not KMSVerifier(cfg).verify():
            missing = True

    # ── 11. Final summary ──────────────────────────────────────────────
    _print_summary(cfg, tf, missing=missing)

    return 3 if missing else 0


# ── Helpers ──────────────────────────────────────────────────────────────

def _check_credentials(cfg: DeployConfig) -> None:
    """Check if AWS credentials are available."""
    if cfg.aws_access_key_id and cfg.aws_secret_access_key:
        console.ok("Credenciais AWS via environment variables")
        return

    # Try boto3 default session
    try:
        import boto3
        sts = boto3.client("sts", region_name=cfg.aws_region)
        sts.get_caller_identity()
        console.ok("Credenciais AWS ativas (SSO / instance profile / environment)")
        return
    except Exception:
        pass

    # Check ~/.aws/credentials
    cred_path = Path.home() / ".aws" / "credentials"
    if cred_path.exists():
        console.ok("Credenciais AWS via aws configure")

    console.warn(
        "Nenhuma credencial AWS encontrada.",
        "Configure com 'aws configure' ou exporte AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY."
    )


def _print_summary(
    cfg: DeployConfig,
    tf: TerraformRunner,
    missing: bool = False,
) -> None:
    """Print the final summary panel."""
    console.section_header("Final Summary")

    api_url = tf.get_output("api_invoke_url") or "<missing>"
    api_key = tf.get_output("api_key_value") or "<missing>"

    notebook_env = cfg.project_root / "app" / "get_flights_data" / "src" / ".env"

    if not missing:
        console.console.print(
            console.summary_panel(
                "🎉 Deployment concluído e verificado com sucesso!",
                [
                    ("API_BASE_URL", api_url),
                    ("API_KEY", api_key),
                    ("Notebook .env", str(notebook_env)),
                ],
                border_style="green",
            )
        )
    else:
        console.console.print(
            console.summary_panel(
                "⚠️  Verificação encontrou recursos faltando",
                [
                    ("API_BASE_URL", api_url),
                    ("API_KEY", api_key),
                    ("Notebook .env", str(notebook_env)),
                ],
                border_style="red",
            )
        )

    console.console.print("\n[bold]Próximos passos:[/bold]")
    console.console.print(
        f"  1. Cole API_BASE_URL e API_KEY em [cyan]{notebook_env}[/cyan]"
    )
    console.console.print("  2. Reinicie o kernel do notebook e rode a cell 'smoke-test-api'")
    console.console.print(
        f'  3. Smoke test: curl -X POST "{api_url}/flights" \\\n'
        f'          -H "X-Api-Key: {api_key}" \\\n'
        f'          -H \'Content-Type: application/json\' \\\n'
        f'          -d \'{{"icao24":"abc123","callsign":"TEST01"}}\''
    )
    console.console.print(
        f"  4. Logs: aws logs tail /aws/lambda/{cfg.project_name}-flights-raw "
        f"--follow --region {cfg.aws_region}"
    )
    console.console.print()


if __name__ == "__main__":
    main()
