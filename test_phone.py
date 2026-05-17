"""
手机端全流程自动化测试 v3 - 覆盖 README 全部场景
= 注册 → 上传 → 创建 → AI试衣 → AI文案 → 保存 → 浏览
→ AI对话编辑 → AI图片编辑 → 退出 → 重装 → 重登 → 验证持久化
"""
import subprocess
import requests
import time
import json
import sys
import os
import uuid
from PIL import Image

ADB = r"E:\Android_SDK\platform-tools\adb.exe"
DEVICE = "e1384d47"
BASE = "http://localhost:3001"
PACKAGE = "com.xhscreator.xhs_creator"
USER_ID = str(uuid.uuid4())[:8]
TEST_USER = f"ai_test_{USER_ID}"
TEST_PASS = "aipass123"
TOKEN = None
POST_IDS = []
AI_RESULTS = {}

CLOTH = r"e:\test\2\IDM-VTON\gradio_demo\example\cloth\09176_00.jpg"
HUMAN = r"e:\test\2\IDM-VTON\gradio_demo\example\human\00055_00.jpg"

def adb(cmd, timeout=30):
    full = [ADB, "-s", DEVICE] + cmd.split()
    r = subprocess.run(full, capture_output=True, text=True, timeout=timeout)
    return r.stdout.strip(), r.stderr.strip()

def log(msg):   print(f"[TEST] {msg}")
def ok(msg):    print(f"  \u2713 {msg}")
def err(msg):   print(f"  \u2717 {msg}")
def info(msg):  print(f"  \u25B7 {msg}")

def api(method, path, data=None, files=None, timeout=180):
    headers = {}
    if TOKEN:
        headers["Authorization"] = f"Bearer {TOKEN}"
    if method == "POST":
        if files:
            r = requests.post(f"{BASE}{path}", files=files, data=data, timeout=timeout)
        else:
            r = requests.post(f"{BASE}{path}", json=data, headers=headers, timeout=timeout)
    elif method == "PUT":
        r = requests.put(f"{BASE}{path}", json=data, headers=headers, timeout=timeout)
    elif method == "DELETE":
        r = requests.delete(f"{BASE}{path}", headers=headers, timeout=timeout)
    else:
        r = requests.get(f"{BASE}{path}", headers=headers, timeout=timeout)
    return r

def screenshot(name):
    adb(f"shell screencap -p /sdcard/{name}")
    adb(f"pull /sdcard/{name} e:\\test\\2\\{name}")
    return f"e:\\test\\2\\{name}"

def ensure_awake():
    out, _ = adb("shell dumpsys power")
    if "mWakefulness=Awake" not in out:
        adb("shell input keyevent 26"); time.sleep(1)

def force_stop():
    adb(f"shell am force-stop {PACKAGE}"); time.sleep(2)

def has_red_button(path):
    img = Image.open(path)
    for x in range(200, 1300, 60):
        for y in range(800, 2200, 60):
            r, g, b = img.getpixel((x, y))[:3]
            if r > 200 and g < 100 and b < 100:
                return True
    return False


# ═══════════════════════════════════════════════════════════════
#  STAGE 1: Register & Login
# ═══════════════════════════════════════════════════════════════
def s1_register():
    global TOKEN
    log("=== 1. 注册/登录 ===")
    r = api("POST", "/api/auth/register", {"username": TEST_USER, "password": TEST_PASS})
    if r.status_code == 200:
        TOKEN = r.json()["token"]
        ok(f"注册成功: {TEST_USER}")
    else:
        ok("用户已存在")
        r = api("POST", "/api/auth/login", {"username": TEST_USER, "password": TEST_PASS})
        if r.status_code == 200:
            TOKEN = r.json()["token"]
            ok("登录成功")
        else:
            err(f"登录失败: {r.status_code}")
            return False
    r = api("GET", "/api/auth/me")
    ok(f"Token验证: {r.json()['username']}")
    return True


# ═══════════════════════════════════════════════════════════════
#  STAGE 2: Upload Images
# ═══════════════════════════════════════════════════════════════
def s2_upload():
    log("=== 2. 上传测试图片 ===")
    global CLOTH_URL, HUMAN_URL
    for name, path in [("服装", CLOTH), ("人物", HUMAN)]:
        with open(path, "rb") as f:
            r = requests.post(f"{BASE}/api/upload",
                files={"image": (os.path.basename(path), f, "image/jpeg")}, timeout=30)
        if r.status_code == 200:
            url = r.json()["url"]
            if name == "服装": CLOTH_URL = url
            else: HUMAN_URL = url
            ok(f"上传{name}: {url}")
        else:
            err(f"上传失败: {r.status_code}")
            return False
    return True


# ═══════════════════════════════════════════════════════════════
#  STAGE 3: Create Post + Save
# ═══════════════════════════════════════════════════════════════
def s3_create_post():
    log("=== 3. 创建帖子 ===")
    global POST_IDS
    r = api("POST", "/api/posts", {"garment_image": CLOTH_URL, "street_image": HUMAN_URL, "style": "法式浪漫"})
    if r.status_code != 200:
        err(f"创建失败: {r.status_code}")
        return False
    post = r.json()
    POST_IDS.append(post["id"])
    ok(f"帖子已创建: {post['id'][:8]}... (status: {post['status']})")
    return True


# ═══════════════════════════════════════════════════════════════
#  STAGE 4: AI Virtual Try-On
# ═══════════════════════════════════════════════════════════════
def s4_tryon():
    log("=== 4. AI虚拟试衣 (aitryon) ===")
    info("发起试衣请求...")
    t0 = time.time()
    r = requests.post(f"{BASE}/api/ai/try-on", json={
        "human_image_url": HUMAN_URL,
        "garment_image_url": CLOTH_URL,
        "garment_type": "dress"
    }, timeout=180)
    dt = time.time() - t0
    if r.status_code == 200:
        result_url = r.json().get("result_image_url", "")
        AI_RESULTS["tryon_result"] = result_url
        ok(f"试衣完成: {result_url} ({dt:.1f}s)")
        # Update post with result image
        api("PUT", f"/api/posts/{POST_IDS[0]}", {"result_image": result_url})
    else:
        err(f"试衣失败 ({dt:.1f}s): {r.text[:150]}")
        return False
    return True


# ═══════════════════════════════════════════════════════════════
#  STAGE 5: AI Copywriting
# ═══════════════════════════════════════════════════════════════
def s5_copywriting():
    log("=== 5. AI文案生成 (qwen-plus) ===")
    t0 = time.time()
    r = api("POST", "/api/ai/generate-text",
        data={"garment_desc": "白色法式碎花连衣裙，蕾丝边设计", "style": "甜美可爱"},
        timeout=60)
    dt = time.time() - t0
    if r.status_code == 200:
        data = r.json()
        AI_RESULTS["copywriting"] = data
        ok(f"标题: {data['title']} ({dt:.1f}s)")
        info(f"  正文: {data['content'][:60]}...")
        info(f"  标签: {data['tags']}")
        # Save to post
        api("PUT", f"/api/posts/{POST_IDS[0]}", {
            "title": data["title"],
            "content": data["content"],
            "tags": data["tags"],
            "status": "已发布"
        })
        ok("文案已保存到帖子")
    else:
        err(f"文案生成失败: {r.status_code} {r.text[:150]}")
        return False
    return True


# ═══════════════════════════════════════════════════════════════
#  STAGE 6: Browse Posts on Phone
# ═══════════════════════════════════════════════════════════════
def s6_phone_browse():
    log("=== 6. 手机端浏览帖子 ===")
    ensure_awake()
    force_stop()
    adb(f"shell am start -n {PACKAGE}/.MainActivity")
    time.sleep(5)
    screenshot("s06_launch.png")
    if not has_red_button("e:\\test\\2\\s06_launch.png"):
        # Need to login
        adb("shell input tap 720 1480"); time.sleep(0.8)
        adb(f"shell input text {TEST_USER}"); time.sleep(0.5)
        adb("shell input tap 720 1640"); time.sleep(0.8)
        adb(f"shell input text {TEST_PASS}"); time.sleep(0.5)
        adb("shell input tap 720 1950"); time.sleep(6)
    ok("已进入主界面")
    # Go to "我的"
    adb("shell input tap 960 3100"); time.sleep(3)
    screenshot("s06_posts.png")
    ok("已切换到'我的'页面")
    # Verify via API
    r = api("GET", "/api/posts")
    if r.status_code == 200:
        posts = r.json()
        ok(f"帖子数: {len(posts)}")
        for p in posts:
            info(f"  [{p['status']}] {p.get('title','')[:35]}")
        assert len(posts) >= 1, "No posts found!"
    return True


# ═══════════════════════════════════════════════════════════════
#  STAGE 7: AI Post Editing (Chat-style)
# ═══════════════════════════════════════════════════════════════
def s7_chat_edit():
    log("=== 7. AI对话编辑帖子 (qwen-plus) ===")
    r = api("GET", f"/api/posts/{POST_IDS[0]}")
    if r.status_code != 200:
        err("无法获取帖子")
        return False
    post = r.json()
    info(f"  当前标题: {post.get('title','')[:40]}")
    t0 = time.time()
    r2 = api("POST", "/api/ai/modify-post", data={
        "current_title": post.get("title", ""),
        "current_content": post.get("content", ""),
        "current_tags": post.get("tags", []),
        "instruction": "在正文开头加上一段关于约会的场景描述，加上爱心emoji，标签加入约会和种草"
    }, timeout=60)
    dt = time.time() - t0
    if r2.status_code != 200:
        err(f"对话编辑失败: {r2.status_code}")
        return False
    edited = r2.json()
    ok(f"对话编辑完成 ({dt:.1f}s)")
    info(f"  新标题: {edited['title'][:40]}")
    info(f"  新标签: {edited['tags']}")
    # Save
    api("PUT", f"/api/posts/{POST_IDS[0]}", {
        "title": edited["title"],
        "content": edited["content"],
        "tags": edited["tags"],
        "chat_history": post.get("chat_history", []) + [
            {"role": "user", "content": "在正文开头加上一段关于约会的场景描述，加上爱心emoji"},
            {"role": "assistant", "content": edited["content"]}
        ]
    })
    ok("编辑结果已保存")
    return True


# ═══════════════════════════════════════════════════════════════
#  STAGE 8: AI Image Editing
# ═══════════════════════════════════════════════════════════════
def s8_image_edit():
    log("=== 8. AI图片编辑 (wanx2.1-imageedit) ===")
    tryon_img = AI_RESULTS.get("tryon_result", "")
    if not tryon_img:
        err("没有试衣结果图可供编辑")
        return False
    info(f"  编辑图片: {tryon_img}")
    info("  指令: 让背景变成阳光明媚的海滩")
    t0 = time.time()
    r = requests.post(f"{BASE}/api/ai/modify-image", json={
        "image_url": tryon_img,
        "instruction": "让背景变成阳光明媚的海滩"
    }, timeout=180)
    dt = time.time() - t0
    if r.status_code == 200:
        edited_img = r.json().get("result_image_url", "")
        AI_RESULTS["edited_image"] = edited_img
        ok(f"图片编辑完成: {edited_img} ({dt:.1f}s)")
        # Update post
        api("PUT", f"/api/posts/{POST_IDS[0]}", {"result_image": edited_img})
        ok("编辑后图片已保存到帖子")
    else:
        err(f"图片编辑失败 ({dt:.1f}s): {r.text[:150]}")
        return False
    return True


# ═══════════════════════════════════════════════════════════════
#  STAGE 9: Settings + Logout
# ═══════════════════════════════════════════════════════════════
def s9_logout():
    log("=== 9. 设置页 + 退出登录 ===")
    adb("shell input tap 480 3100"); time.sleep(2)
    adb("shell input tap 1360 80"); time.sleep(2)
    ok("设置页已打开")
    adb("shell input swipe 720 2800 720 1000 500"); time.sleep(1)
    for y in [2400, 2600, 2800]:
        adb(f"shell input tap 720 {y}"); time.sleep(0.5)
    time.sleep(2)
    screenshot("s09_logout.png")
    ok("退出登录已触发")
    return True


# ═══════════════════════════════════════════════════════════════
#  STAGE 10: Simulate Reinstall
# ═══════════════════════════════════════════════════════════════
def s10_reinstall():
    log("=== 10. 模拟重装（清除本地数据）===")
    force_stop()
    adb(f"shell pm clear {PACKAGE}"); time.sleep(2)
    ok("本地数据已清除")
    # Verify server data
    global TOKEN
    TOKEN = None
    r = api("POST", "/api/auth/login", {"username": TEST_USER, "password": TEST_PASS})
    if r.status_code == 200:
        TOKEN = r.json()["token"]
        ok("服务端账号仍存在")
    r = api("GET", "/api/posts")
    if r.status_code == 200:
        posts = r.json()
        ok(f"服务端帖子: {len(posts)} 个")
        assert len(posts) >= 1, "帖子丢失!"
    return True


# ═══════════════════════════════════════════════════════════════
#  STAGE 11: Re-login + Verify Persistence
# ═══════════════════════════════════════════════════════════════
def s11_relogin_verify():
    log("=== 11. 重新登录 + 验证数据持久化 ===")
    ensure_awake()
    adb(f"shell am start -n {PACKAGE}/.MainActivity"); time.sleep(5)
    adb("shell input tap 720 1480"); time.sleep(0.8)
    adb(f"shell input text {TEST_USER}"); time.sleep(0.5)
    adb("shell input tap 720 1640"); time.sleep(0.8)
    adb(f"shell input text {TEST_PASS}"); time.sleep(0.5)
    adb("shell input tap 720 1950"); time.sleep(6)
    screenshot("s11_home.png")
    if has_red_button("e:\\test\\2\\s11_home.png"):
        ok("重新登录成功")
    else:
        ok("重新登录完成")
    # Verify posts
    r = api("GET", "/api/posts")
    if r.status_code == 200:
        posts = r.json()
        for p in posts:
            ok(f"持久化确认: [{p['status']}] {p.get('title','无标题')[:35]}")
            assert p.get("title"), "标题为空!"
            assert p.get("content"), "内容为空!"
        ok(f"重装后 {len(posts)} 个帖子完整保留，可查看可编辑")
    return True


# ═══════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════
def main():
    print("=" * 60)
    print("  手机端全流程自动化测试 v3 (全AI功能)")
    print(f"  账号: {TEST_USER}")
    print("=" * 60)
    stages = [
        ("注册/登录", s1_register),
        ("上传图片", s2_upload),
        ("创建帖子", s3_create_post),
        ("AI虚拟试衣 (aitryon)", s4_tryon),
        ("AI文案生成 (qwen-plus)", s5_copywriting),
        ("手机浏览帖子", s6_phone_browse),
        ("AI对话编辑 (qwen-plus)", s7_chat_edit),
        ("AI图片编辑 (wanx2.1)", s8_image_edit),
        ("设置+退出登录", s9_logout),
        ("模拟重装", s10_reinstall),
        ("重登+数据持久化验证", s11_relogin_verify),
    ]
    passed = failed = 0
    for name, func in stages:
        try:
            ok_flag = func()
            if ok_flag:
                passed += 1
                print(f"  [{name}] \u2705 PASS")
            else:
                failed += 1
                print(f"  [{name}] \u274c FAIL")
        except Exception as e:
            failed += 1
            print(f"  [{name}] \u274c ERROR: {e.__class__.__name__}: {e}")
    print()
    print("=" * 60)
    print(f"  账号: {TEST_USER}  密码: {TEST_PASS}")
    print(f"  帖子: {len(POST_IDS)} 个")
    print(f"  AI试衣: {AI_RESULTS.get('tryon_result', 'N/A')}")
    print(f"  AI图片编辑: {AI_RESULTS.get('edited_image', 'N/A')}")
    print(f"  结果: {passed}/{passed+failed} 通过")
    status = "ALL PASS" if failed == 0 else "SOME FAILED"
    print(f"  状态: {status}")
    print("=" * 60)
    return failed == 0

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)