import os
import json
import uuid
import shutil
import hashlib
import secrets
import asyncio
from pathlib import Path
from typing import Optional
from dotenv import load_dotenv

load_dotenv()

from fastapi import FastAPI, File, UploadFile, Form, Header, Request
from fastapi.responses import FileResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
import uvicorn

BASE_DIR = Path(__file__).parent
UPLOADS_DIR = BASE_DIR / "uploads"
DATA_DIR = BASE_DIR / "data"
UPLOADS_DIR.mkdir(exist_ok=True)
DATA_DIR.mkdir(exist_ok=True)

DB_PATH = DATA_DIR / "db.json"

DASHSCOPE_API_KEY = os.environ.get("DASHSCOPE_API_KEY", "")
AITRYON_MODEL = os.environ.get("AITRYON_MODEL", "aitryon")
QWEN_MODEL = os.environ.get("QWEN_MODEL", "qwen-plus")
IMAGE_EDIT_MODEL = os.environ.get("IMAGE_EDIT_MODEL", "wanx2.1-imageedit")
PORT = int(os.environ.get("PORT", "3001"))
PUBLIC_BASE_URL = os.environ.get("PUBLIC_BASE_URL", "")

DASHSCOPE_BASE = "https://dashscope.aliyuncs.com"

# 原始URL映射：本地文件名 → 原始HTTPS URL
_original_url_map: dict[str, str] = {}

app = FastAPI(title="XHS Creator Backend")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)
app.mount("/uploads", StaticFiles(directory=str(UPLOADS_DIR)), name="uploads")


def read_db() -> dict:
    if not DB_PATH.exists():
        db = {"users": {}, "posts": {}}
        DB_PATH.write_text(json.dumps(db, ensure_ascii=False, indent=2), encoding="utf-8")
        return db
    try:
        raw = DB_PATH.read_text(encoding="utf-8").strip()
        if not raw:
            db = {"users": {}, "posts": {}}
            DB_PATH.write_text(json.dumps(db, ensure_ascii=False, indent=2), encoding="utf-8")
            return db
        return json.loads(raw)
    except (json.JSONDecodeError, Exception):
        db = {"users": {}, "posts": {}}
        DB_PATH.write_text(json.dumps(db, ensure_ascii=False, indent=2), encoding="utf-8")
        return db


def write_db(db: dict):
    tmp_path = DB_PATH.with_suffix('.tmp')
    data = json.dumps(db, ensure_ascii=False, indent=2)
    tmp_path.write_text(data, encoding="utf-8")
    tmp_path.replace(DB_PATH)


def resolve_image_path(image_ref: str) -> Optional[str]:
    if not image_ref:
        return None
    if (UPLOADS_DIR / image_ref).exists():
        return str(UPLOADS_DIR / image_ref)
    if Path(image_ref).exists():
        return image_ref
    if image_ref.startswith("/uploads/"):
        local = UPLOADS_DIR / image_ref.replace("/uploads/", "")
        if local.exists():
            return str(local)
    return None


def get_image_public_url(image_ref: str) -> Optional[str]:
    if not image_ref:
        return None
    if image_ref.startswith("http"):
        return image_ref
    if PUBLIC_BASE_URL:
        return f"{PUBLIC_BASE_URL}{image_ref}"
    return None


async def _upload_to_oss(local_path: str, model: str = "aitryon") -> Optional[str]:
    import httpx
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.get(
            f"{DASHSCOPE_BASE}/api/v1/uploads",
            headers={"Authorization": f"Bearer {DASHSCOPE_API_KEY}"},
            params={"action": "getPolicy", "model": model},
        )
        if resp.status_code != 200:
            print(f"[Upload] Get policy failed: {resp.status_code} {resp.text}")
            return None
        policy_data = resp.json().get("data")
        if not policy_data:
            print(f"[Upload] No policy data: {resp.text}")
            return None

        upload_host = policy_data["upload_host"]
        upload_dir = policy_data["upload_dir"]
        filename = Path(local_path).name
        key = f"{upload_dir}/{filename}"

        with open(local_path, "rb") as f:
            upload_resp = await client.post(
                upload_host,
                data={
                    "OSSAccessKeyId": policy_data["oss_access_key_id"],
                    "Signature": policy_data["signature"],
                    "policy": policy_data["policy"],
                    "x-oss-object-acl": policy_data["x_oss_object_acl"],
                    "x-oss-forbid-overwrite": policy_data["x_oss_forbid_overwrite"],
                    "key": key,
                    "success_action_status": "200",
                },
                files={
                    "file": (filename, f, "image/png" if filename.lower().endswith(".png") else "image/jpeg"),
                },
            )
            if upload_resp.status_code != 200:
                print(f"[Upload] OSS upload failed: {upload_resp.status_code} {upload_resp.text}")
                return None

        oss_url = f"oss://{key}"
        print(f"[Upload] Success: {oss_url}")
        return oss_url


# ==================== Auth ====================

SESSION_TOKENS: dict[str, str] = {}  # token -> user_id


def _hash_password(password: str) -> str:
    salt = secrets.token_hex(16)
    h = hashlib.sha256(f"{salt}:{password}".encode()).hexdigest()
    return f"{salt}:{h}"


def _verify_password(password: str, stored: str) -> bool:
    parts = stored.split(":", 1)
    if len(parts) != 2:
        return False
    salt, h = parts
    return hashlib.sha256(f"{salt}:{password}".encode()).hexdigest() == h


def _generate_token(user_id: str) -> str:
    token = str(uuid.uuid4())
    SESSION_TOKENS[token] = user_id
    return token


def _get_user_id_from_token(token: str) -> Optional[str]:
    return SESSION_TOKENS.get(token)


def _get_user_id_from_req(authorization: Optional[str]) -> Optional[str]:
    if authorization and authorization.startswith("Bearer "):
        return _get_user_id_from_token(authorization[7:])
    return None


@app.post("/api/auth/register")
async def register(request: Request):
    body = await request.json()
    username = (body.get("username") or "").strip()
    password = (body.get("password") or "").strip()

    if not username or not password:
        return JSONResponse({"error": "用户名和密码不能为空"}, status_code=400)
    if len(username) < 2 or len(username) > 32:
        return JSONResponse({"error": "用户名需要 2-32 个字符"}, status_code=400)
    if len(password) < 6 or len(password) > 64:
        return JSONResponse({"error": "密码需要 6-64 个字符"}, status_code=400)

    db = read_db()
    for u in db["users"].values():
        if u.get("username") == username:
            return JSONResponse({"error": "用户名已被注册"}, status_code=409)

    user_id = str(uuid.uuid4())
    user = {
        "id": user_id,
        "username": username,
        "password_hash": _hash_password(password),
        "nickname": username,
        "avatar": "",
        "created_at": _now(),
    }
    db["users"][user_id] = user
    write_db(db)

    token = _generate_token(user_id)
    return {"user": {k: v for k, v in user.items() if k != "password_hash"}, "token": token}


@app.post("/api/auth/login")
async def login(request: Request):
    body = await request.json()
    username = (body.get("username") or "").strip()
    password = (body.get("password") or "").strip()

    if not username or not password:
        return JSONResponse({"error": "用户名和密码不能为空"}, status_code=400)

    db = read_db()
    for u in db["users"].values():
        if u.get("username") == username:
            if _verify_password(password, u.get("password_hash", "")):
                token = _generate_token(u["id"])
                return {"user": {k: v for k, v in u.items() if k != "password_hash"}, "token": token}
            else:
                return JSONResponse({"error": "密码错误"}, status_code=401)

    return JSONResponse({"error": "用户名不存在"}, status_code=404)


@app.get("/api/auth/me")
async def me(authorization: Optional[str] = Header(None)):
    token = None
    if authorization and authorization.startswith("Bearer "):
        token = authorization[7:]

    if not token:
        return JSONResponse({"error": "Unauthorized"}, status_code=401)

    user_id = _get_user_id_from_token(token)
    if not user_id:
        return JSONResponse({"error": "Token 无效或已过期"}, status_code=401)

    db = read_db()
    user = db["users"].get(user_id)
    if not user:
        return JSONResponse({"error": "User not found"}, status_code=404)
    return {k: v for k, v in user.items() if k != "password_hash"}


@app.post("/api/auth/logout")
async def logout(authorization: Optional[str] = Header(None)):
    token = None
    if authorization and authorization.startswith("Bearer "):
        token = authorization[7:]
    if token:
        SESSION_TOKENS.pop(token, None)
    return {"status": "ok"}


# ==================== Upload ====================

@app.post("/api/upload")
async def upload_image(image: UploadFile = File(...), original_url: Optional[str] = Form(None)):
    ext = Path(image.filename or ".jpg").suffix or ".jpg"
    filename = f"{uuid.uuid4()}{ext}"
    filepath = UPLOADS_DIR / filename
    content = await image.read()
    filepath.write_bytes(content)
    result = {"url": f"/uploads/{filename}", "filename": filename}
    if original_url:
        _original_url_map[filename] = original_url
        result["original_url"] = original_url
    return result


# ==================== Posts CRUD ====================

@app.post("/api/posts")
async def create_post(request: Request, authorization: Optional[str] = Header(None)):
    user_id = _get_user_id_from_req(authorization)
    if not user_id:
        return JSONResponse({"error": "Unauthorized"}, status_code=401)
    body = await request.json()
    db = read_db()
    post_id = str(uuid.uuid4())
    post = {
        "id": post_id,
        "user_id": user_id,
        "garment_image": body.get("garment_image", ""),
        "street_image": body.get("street_image", ""),
        "result_image": "",
        "title": "",
        "content": "",
        "tags": [],
        "style": body.get("style", ""),
        "chat_history": [],
        "status": "draft",
        "created_at": _now(),
        "updated_at": _now(),
    }
    db["posts"][post_id] = post
    write_db(db)
    return post


@app.get("/api/posts")
async def list_posts(authorization: Optional[str] = Header(None)):
    user_id = _get_user_id_from_req(authorization)
    if not user_id:
        return JSONResponse({"error": "Unauthorized"}, status_code=401)
    db = read_db()
    posts = [p for p in db["posts"].values() if p["user_id"] == user_id]
    posts.sort(key=lambda p: p.get("updated_at", ""), reverse=True)
    return posts


@app.get("/api/posts/{post_id}")
async def get_post(post_id: str):
    db = read_db()
    post = db["posts"].get(post_id)
    if not post:
        return JSONResponse({"error": "Post not found"}, status_code=404)
    return post


@app.put("/api/posts/{post_id}")
async def update_post(post_id: str, request: Request):
    db = read_db()
    post = db["posts"].get(post_id)
    if not post:
        return JSONResponse({"error": "Post not found"}, status_code=404)
    body = await request.json()
    for key in ["title", "content", "tags", "result_image", "style", "chat_history", "status"]:
        if key in body:
            post[key] = body[key]
    post["updated_at"] = _now()
    db["posts"][post_id] = post
    write_db(db)
    return post


@app.delete("/api/posts/{post_id}")
async def delete_post(post_id: str):
    db = read_db()
    if post_id in db["posts"]:
        del db["posts"][post_id]
        write_db(db)
    return {"success": True}


# ==================== AI: Virtual Try-On (阿里百炼 aitryon) ====================

@app.post("/api/ai/try-on")
async def api_try_on(request: Request):
    body = await request.json()
    human_image_url = body.get("human_image_url", "")
    garment_image_url = body.get("garment_image_url", "")
    garment_type = body.get("garment_type", "upper_body")

    if not human_image_url or not garment_image_url:
        return JSONResponse({"error": "Both images are required"}, status_code=400)

    if not DASHSCOPE_API_KEY:
        return JSONResponse({"error": "DASHSCOPE_API_KEY not configured"}, status_code=500)

    import httpx

    person_url = await _ensure_public_url(human_image_url)
    garment_url = await _ensure_public_url(garment_image_url)

    if not person_url or not garment_url:
        return JSONResponse({"error": "Failed to get public URL for images"}, status_code=500)

    try:
        input_data = {"person_image_url": person_url}
        if garment_type in ("upper_body", "dress"):
            input_data["top_garment_url"] = garment_url
        else:
            input_data["bottom_garment_url"] = garment_url

        async with httpx.AsyncClient(timeout=60) as client:
            resp = await client.post(
                f"{DASHSCOPE_BASE}/api/v1/services/aigc/image2image/image-synthesis",
                headers={
                    "Authorization": f"Bearer {DASHSCOPE_API_KEY}",
                    "Content-Type": "application/json",
                    "X-DashScope-Async": "enable",
                    "X-DashScope-OssResourceResolve": "enable",
                },
                json={
                    "model": AITRYON_MODEL,
                    "input": input_data,
                    "parameters": {"resolution": -1, "restore_face": True},
                },
            )
            data = resp.json()

        if "output" not in data or "task_id" not in data.get("output", {}):
            print(f"[TryOn] Create task failed: {data}")
            return JSONResponse({"error": f"Create task failed: {data.get('message', 'unknown')}"}, status_code=500)

        task_id = data["output"]["task_id"]
        print(f"[TryOn] Task created: {task_id}, polling...")

        for _ in range(60):
            await asyncio.sleep(3)
            async with httpx.AsyncClient(timeout=30) as client:
                resp = await client.get(
                    f"{DASHSCOPE_BASE}/api/v1/tasks/{task_id}",
                    headers={"Authorization": f"Bearer {DASHSCOPE_API_KEY}"},
                )
                result = resp.json()

            status = result.get("output", {}).get("task_status", "")
            print(f"[TryOn] Task {task_id}: {status}")

            if status == "SUCCEEDED":
                image_url = result["output"].get("image_url", "")
                if image_url:
                    local_path = await _download_to_uploads(image_url)
                    if local_path:
                        return {"result_image_url": local_path}
                return JSONResponse({"error": "No image URL in result"}, status_code=500)

            if status in ("FAILED", "UNKNOWN", "CANCELED"):
                msg = result.get("output", {}).get("message", "Task failed")
                return JSONResponse({"error": msg}, status_code=500)

        return JSONResponse({"error": "Try-on timeout (180s)"}, status_code=504)

    except Exception as e:
        print(f"[TryOn] Error: {e}")
        import traceback
        traceback.print_exc()
        return JSONResponse({"error": str(e)}, status_code=500)


# ==================== AI: Generate Text (阿里百炼 通义千问) ====================

@app.post("/api/ai/generate-text")
async def api_generate_text(request: Request):
    body = await request.json()
    garment_desc = body.get("garment_desc", "")
    style = body.get("style", "")
    existing_content = body.get("existing_content", "")

    if not garment_desc:
        return JSONResponse({"error": "garment_desc is required"}, status_code=400)

    if not DASHSCOPE_API_KEY:
        return JSONResponse({"error": "DASHSCOPE_API_KEY not configured"}, status_code=500)

    try:
        import httpx
        system_prompt = """你是一个专业的小红书种草文案写手。根据用户提供的服装描述和风格要求，生成吸引人的小红书帖子文案。
要求：
1. 标题要有吸引力，使用emoji，控制在20字以内
2. 正文要有种草感，语气亲切自然，像朋友推荐一样
3. 适当使用emoji增加趣味性
4. 包含3-5个相关话题标签
5. 正文300-500字
6. 返回JSON格式：{"title": "标题", "content": "正文内容", "tags": ["标签1", "标签2"]}"""

        user_prompt = f"服装描述：{garment_desc}\n风格要求：{style}"
        if existing_content:
            user_prompt += f"\n已有内容（请在此基础上优化）：{existing_content}"

        async with httpx.AsyncClient(timeout=60) as client:
            resp = await client.post(
                f"{DASHSCOPE_BASE}/compatible-mode/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {DASHSCOPE_API_KEY}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": QWEN_MODEL,
                    "messages": [
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": user_prompt},
                    ],
                    "temperature": 0.8,
                    "response_format": {"type": "json_object"},
                },
            )
            result = resp.json()
            content = result["choices"][0]["message"]["content"]
            return json.loads(content)

    except Exception as e:
        print(f"[Qwen] Generate error: {e}")
        return JSONResponse({"error": str(e)}, status_code=500)


# ==================== AI: Modify Post (阿里百炼 通义千问) ====================

@app.post("/api/ai/modify-post")
async def api_modify_post(request: Request):
    body = await request.json()
    current_title = body.get("current_title", "")
    current_content = body.get("current_content", "")
    current_tags = body.get("current_tags", [])
    instruction = body.get("instruction", "")

    if not instruction:
        return JSONResponse({"error": "instruction is required"}, status_code=400)

    if not DASHSCOPE_API_KEY:
        return JSONResponse({"error": "DASHSCOPE_API_KEY not configured"}, status_code=500)

    try:
        import httpx
        system_prompt = """你是一个专业的小红书种草文案写手。用户会给你当前的帖子内容和修改指令，你需要根据指令修改内容。
返回JSON格式：{"title": "修改后的标题", "content": "修改后的正文", "tags": ["修改后的标签1", "修改后的标签2"]}"""
        user_prompt = f"当前标题：{current_title}\n当前正文：{current_content}\n当前标签：{','.join(current_tags)}\n修改指令：{instruction}"

        async with httpx.AsyncClient(timeout=60) as client:
            resp = await client.post(
                f"{DASHSCOPE_BASE}/compatible-mode/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {DASHSCOPE_API_KEY}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": QWEN_MODEL,
                    "messages": [
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": user_prompt},
                    ],
                    "temperature": 0.7,
                    "response_format": {"type": "json_object"},
                },
            )
            result = resp.json()
            content = result["choices"][0]["message"]["content"]
            return json.loads(content)

    except Exception as e:
        print(f"[Qwen] Modify error: {e}")
        return JSONResponse({"error": str(e)}, status_code=500)


# ==================== AI: Modify Image (万相 wanx2.1-imageedit) ====================

@app.post("/api/ai/modify-image")
async def api_modify_image(request: Request):
    body = await request.json()
    image_url = body.get("image_url", "")
    instruction = body.get("instruction", "")

    if not image_url or not instruction:
        return JSONResponse({"error": "image_url and instruction are required"}, status_code=400)

    if not DASHSCOPE_API_KEY:
        return JSONResponse({"error": "DASHSCOPE_API_KEY not configured"}, status_code=500)

    public_url = await _ensure_public_url(image_url)
    if not public_url:
        return JSONResponse({"error": "Failed to get public URL for image"}, status_code=500)

    try:
        import httpx
        async with httpx.AsyncClient(timeout=60) as client:
            resp = await client.post(
                f"{DASHSCOPE_BASE}/api/v1/services/aigc/image2image/image-synthesis",
                headers={
                    "Authorization": f"Bearer {DASHSCOPE_API_KEY}",
                    "Content-Type": "application/json",
                    "X-DashScope-Async": "enable",
                    "X-DashScope-OssResourceResolve": "enable",
                },
                json={
                    "model": IMAGE_EDIT_MODEL,
                    "input": {
                        "function": "description_edit",
                        "prompt": instruction,
                        "base_image_url": public_url,
                    },
                    "parameters": {
                        "n": 1,
                        "watermark": False,
                        "strength": 0.6,
                    },
                },
            )
            data = resp.json()

        if "output" not in data or "task_id" not in data.get("output", {}):
            print(f"[ImageEdit] Create task failed: {data}")
            return JSONResponse({"error": f"Create task failed: {data.get('message', 'unknown')}"}, status_code=500)

        task_id = data["output"]["task_id"]
        print(f"[ImageEdit] Task created: {task_id}, polling...")

        for i in range(60):
            await asyncio.sleep(3)
            async with httpx.AsyncClient(timeout=30) as client:
                resp = await client.get(
                    f"{DASHSCOPE_BASE}/api/v1/tasks/{task_id}",
                    headers={"Authorization": f"Bearer {DASHSCOPE_API_KEY}"},
                )
                result = resp.json()

            status = result.get("output", {}).get("task_status", "")
            print(f"[ImageEdit] Task {task_id}: {status}")

            if status == "SUCCEEDED":
                results = result["output"].get("results", [])
                if results:
                    result_image_url = results[0].get("url", "")
                    if result_image_url:
                        local_path = await _download_to_uploads(result_image_url)
                        if local_path:
                            return {"result_image_url": local_path}
                return JSONResponse({"error": "No image URL in result"}, status_code=500)

            if status in ("FAILED", "UNKNOWN", "CANCELED"):
                msg = result.get("output", {}).get("message", "Task failed")
                return JSONResponse({"error": msg}, status_code=500)

        return JSONResponse({"error": "Image editing timeout (180s)"}, status_code=504)

    except Exception as e:
        print(f"[ImageEdit] Error: {e}")
        import traceback
        traceback.print_exc()
        return JSONResponse({"error": str(e)}, status_code=500)


# ==================== Health ====================

@app.get("/api/health")
async def health():
    return {
        "status": "ok",
        "aitryon_model": AITRYON_MODEL,
        "qwen_model": QWEN_MODEL,
        "image_edit_model": IMAGE_EDIT_MODEL,
        "dashscope_configured": bool(DASHSCOPE_API_KEY),
        "public_base_url": PUBLIC_BASE_URL,
        "timestamp": _now(),
    }


# ==================== Helpers ====================

async def _ensure_public_url(image_ref: str) -> Optional[str]:
    if image_ref.startswith("http"):
        return image_ref
    local = resolve_image_path(image_ref)
    if not local:
        return None

    filename = Path(local).name
    if filename in _original_url_map:
        print(f"[PublicURL] Using original URL for {filename}")
        return _original_url_map[filename]

    if PUBLIC_BASE_URL:
        if image_ref.startswith("/uploads/"):
            return f"{PUBLIC_BASE_URL}{image_ref}"
        return f"{PUBLIC_BASE_URL}/uploads/{filename}"
    oss_url = await _upload_to_oss(local)
    if oss_url:
        return oss_url
    return None


async def _download_to_uploads(url: str) -> Optional[str]:
    import httpx
    try:
        async with httpx.AsyncClient(timeout=60) as client:
            resp = await client.get(url)
            if resp.status_code == 200:
                filename = f"result_{uuid.uuid4().hex}.png"
                filepath = UPLOADS_DIR / filename
                filepath.write_bytes(resp.content)
                return f"/uploads/{filename}"
    except Exception as e:
        print(f"[Download] Error: {e}")
    return None


def _now() -> str:
    from datetime import datetime, timezone
    return datetime.now(timezone.utc).isoformat()


if __name__ == "__main__":
    print(f"XHS Creator Backend (阿里百炼版)")
    print(f"Port: {PORT}")
    print(f"AI试衣模型: {AITRYON_MODEL}")
    print(f"文案模型: {QWEN_MODEL}")
    print(f"图片编辑模型: {IMAGE_EDIT_MODEL}")
    print(f"百炼API Key: {'已配置' if DASHSCOPE_API_KEY else '未配置'}")
    print(f"公网地址: {PUBLIC_BASE_URL or '未配置'}")
    uvicorn.run(app, host="0.0.0.0", port=PORT)
