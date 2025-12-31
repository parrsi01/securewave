from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from database.session import get_db
from models.user import User
from services.jwt_service import get_current_user
from services.wireguard_service import WireGuardService

router = APIRouter()


def get_wg_service(request: Request) -> WireGuardService:
    service: WireGuardService = request.app.state.wireguard
    return service


@router.post("/generate")
def generate_config(
    request: Request, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)
):
    wg_service = get_wg_service(request)
    config_path, config_text = wg_service.generate_client_config(current_user)
    db.add(current_user)
    db.commit()
    return {"message": "WireGuard config generated", "path": str(config_path), "config": config_text}


@router.get("/config/download")
def download_config(
    request: Request, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)
):
    wg_service = get_wg_service(request)
    if not wg_service.config_exists(current_user.id):
        wg_service.generate_client_config(current_user)
        db.add(current_user)
        db.commit()
    config_path = wg_service.users_dir / f"{current_user.id}.conf"
    return FileResponse(config_path, media_type="text/plain", filename="securewave.conf")


@router.get("/config/qr")
def qr_code(request: Request, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    wg_service = get_wg_service(request)
    if not wg_service.config_exists(current_user.id):
        wg_service.generate_client_config(current_user)
        db.add(current_user)
        db.commit()
    config_text = wg_service.get_config(current_user.id)
    qr_base64 = wg_service.qr_from_config(config_text)
    return {"qr_base64": qr_base64}
