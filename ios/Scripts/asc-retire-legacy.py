#!/usr/bin/env python3
"""下线旧版「循环班表」（com.wenjinliu.shiftledger）在 Apple 后台留下的东西。

只认这一个 Bundle ID，别的一律不碰。用仓库已有的 App Store Connect API 密钥
（环境变量 KEY_ID / ISSUER_ID，私钥在 ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8）。

ACTION：
- inspect         只读：列出旧 App、它的 TestFlight 构建、测试组、描述文件、Bundle ID
- expire-builds   让旧 App 的全部 TestFlight 构建过期（测试员不能再安装，不可撤销）
- delete-profiles 删除旧 Bundle ID 的描述文件
- delete-bundle   删除旧 Bundle ID（App Store Connect 里还有这个 App 时 Apple 会拒绝）

破坏性操作要求 CONFIRM 等于旧 Bundle ID。
App Store Connect 里的 App 本身 API 删不掉，要在网页上「App 信息 › 移除 App」。
iCloud 容器 Apple 不允许删除。

依赖：pip install 'pyjwt[crypto]'
"""

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import jwt

API = "https://api.appstoreconnect.apple.com"
LEGACY_BUNDLE_ID = "com.wenjinliu.shiftledger"


def token() -> str:
    key_id = os.environ["KEY_ID"]
    key_path = Path.home() / ".appstoreconnect/private_keys" / f"AuthKey_{key_id}.p8"
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ISSUER_ID"], "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        key_path.read_text(),
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


AUTH = ""


def call(method: str, path: str, params: dict | None = None, body: dict | None = None) -> dict:
    url = path if path.startswith("http") else API + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": f"Bearer {AUTH}",
        "Content-Type": "application/json",
    })
    with urllib.request.urlopen(request, timeout=30) as response:
        raw = response.read()
    return json.loads(raw) if raw else {}


def get_all(path: str, params: dict | None = None) -> list[dict]:
    items: list[dict] = []
    body = call("GET", path, params)
    while True:
        data = body.get("data", [])
        items.extend(data if isinstance(data, list) else [data])
        nxt = body.get("links", {}).get("next")
        if not nxt:
            return items
        body = call("GET", nxt)


def explain(error: urllib.error.HTTPError) -> str:
    try:
        errors = json.loads(error.read()).get("errors", [])
        return "；".join(f"{e.get('title')}: {e.get('detail')}" for e in errors) or str(error)
    except Exception:  # noqa: BLE001
        return str(error)


def main() -> int:
    global AUTH
    AUTH = token()
    action = os.environ.get("ACTION", "inspect").strip()
    if action != "inspect" and os.environ.get("CONFIRM", "").strip() != LEGACY_BUNDLE_ID:
        print(f"::error::{action} 是破坏性操作，CONFIRM 必须填 {LEGACY_BUNDLE_ID}")
        return 1

    apps = get_all("/v1/apps", {"filter[bundleId]": LEGACY_BUNDLE_ID, "fields[apps]": "name,bundleId,sku"})
    app = next((a for a in apps if a["attributes"]["bundleId"] == LEGACY_BUNDLE_ID), None)
    bundles = get_all("/v1/bundleIds", {"filter[identifier]": LEGACY_BUNDLE_ID,
                                        "fields[bundleIds]": "identifier,name"})
    bundle = next((b for b in bundles if b["attributes"]["identifier"] == LEGACY_BUNDLE_ID), None)

    print(f"=== 旧版 {LEGACY_BUNDLE_ID} ===")
    builds: list[dict] = []
    if app:
        a = app["attributes"]
        print(f"App Store Connect：{a['name']!r} sku={a['sku']} appleId={app['id']}")
        builds = get_all("/v1/builds", {"filter[app]": app["id"], "limit": 200,
                                        "fields[builds]": "version,uploadedDate,expired,processingState"})
        for build in sorted(builds, key=lambda b: b["attributes"].get("uploadedDate") or ""):
            b = build["attributes"]
            print(f"  构建 {b['version']:<6} 上传 {b.get('uploadedDate')}  状态 {b.get('processingState')}"
                  f"  {'已过期' if b.get('expired') else '可安装'}")
        groups = get_all(f"/v1/apps/{app['id']}/betaGroups", {"fields[betaGroups]": "name,isInternalGroup"})
        for group in groups:
            g = group["attributes"]
            print(f"  测试组 {g['name']!r}（{'内部' if g.get('isInternalGroup') else '外部'}）")
    else:
        print("App Store Connect 里已经没有这个 App")

    profiles: list[dict] = []
    if bundle:
        print(f"Bundle ID：{bundle['attributes']['identifier']} name={bundle['attributes']['name']!r}")
        profiles = get_all(f"/v1/bundleIds/{bundle['id']}/profiles", {"fields[profiles]": "name,profileType,profileState"})
        for profile in profiles:
            p = profile["attributes"]
            print(f"  描述文件 {p['name']!r}（{p['profileType']}，{p['profileState']}）")
    else:
        print("Apple Developer 里已经没有这个 Bundle ID")

    ok = True
    if action == "expire-builds":
        for build in builds:
            if build["attributes"].get("expired"):
                continue
            try:
                call("PATCH", f"/v1/builds/{build['id']}", body={
                    "data": {"type": "builds", "id": build["id"], "attributes": {"expired": True}}})
                print(f"已让构建 {build['attributes']['version']} 过期")
            except urllib.error.HTTPError as error:
                print(f"::error::构建 {build['attributes']['version']} 过期失败：{explain(error)}")
                ok = False
    elif action == "delete-profiles":
        for profile in profiles:
            try:
                call("DELETE", f"/v1/profiles/{profile['id']}")
                print(f"已删除描述文件 {profile['attributes']['name']!r}")
            except urllib.error.HTTPError as error:
                print(f"::error::删除描述文件失败：{explain(error)}")
                ok = False
    elif action == "delete-bundle":
        if bundle is None:
            print("没有可删的 Bundle ID")
        else:
            try:
                call("DELETE", f"/v1/bundleIds/{bundle['id']}")
                print(f"已删除 Bundle ID {LEGACY_BUNDLE_ID}")
            except urllib.error.HTTPError as error:
                print(f"::warning::Apple 拒绝删除 Bundle ID：{explain(error)}")
                ok = False
    elif action != "inspect":
        print(f"::error::不认识的 ACTION：{action}")
        ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
