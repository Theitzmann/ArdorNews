import os
from datetime import datetime, timezone

import httpx
from dotenv import load_dotenv

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(BASE_DIR, '.env'))

REVENUECAT_SECRET_API_KEY = os.getenv("REVENUECAT_SECRET_API_KEY")
REVENUECAT_API_URL = "https://api.revenuecat.com/v1/subscribers"

# Nome do entitlement configurado na RevenueCat para acesso pago.
# Definido ao criar o entitlement no painel da RevenueCat (Phase B).
ENTITLEMENT_ID = "premium"


async def buscar_estado_assinante(app_user_id: str) -> dict:
    """
    Pergunta à RevenueCat o estado canônico da assinatura de um usuário.
    Devolve {'status': 'active' | 'expired' | 'inactive', 'expires_at': iso | None}.
    """
    if not REVENUECAT_SECRET_API_KEY:
        raise RuntimeError("REVENUECAT_SECRET_API_KEY não configurada")

    headers = {"Authorization": f"Bearer {REVENUECAT_SECRET_API_KEY}"}
    async with httpx.AsyncClient() as client:
        resp = await client.get(
            f"{REVENUECAT_API_URL}/{app_user_id}", headers=headers
        )
        resp.raise_for_status()
        data = resp.json()

    entitlements = data.get("subscriber", {}).get("entitlements", {})
    entitlement = entitlements.get(ENTITLEMENT_ID)

    if not entitlement:
        return {"status": "inactive", "expires_at": None}

    expires_at = entitlement.get("expires_date")
    # A RevenueCat marca entitlements ativos com este campo; se ausente,
    # tratamos como uma concessão sem expiração (ativa).
    ativo = expires_at is None or not _esta_expirado(expires_at)

    return {
        "status": "active" if ativo else "expired",
        "expires_at": expires_at,
    }


def _esta_expirado(expires_at_iso: str) -> bool:
    expira = datetime.fromisoformat(expires_at_iso.replace("Z", "+00:00"))
    return expira < datetime.now(timezone.utc)
