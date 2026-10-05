#!/usr/bin/env python3
"""App Store Connect API 키로 CI 가 만든 개발 인증서("Created via API")를 지운다.

GitHub Actions 러너는 매번 새로 만들어져서 xcodebuild -allowProvisioningUpdates 가 실행마다
Apple Development 인증서를 새로 만든다. 쌓여서 계정 한도에 걸리면 아카이브가 실패하므로
업로드 전후에 CI 가 만든 개발 인증서만 정리한다. 사람이 Xcode 에서 만든 인증서는 건드리지 않는다.

환경 변수: ASC_KEY_ID, ASC_ISSUER_ID, KEY_PATH(.p8 경로)
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt  # PyJWT

API = "https://api.appstoreconnect.apple.com/v1"
DEVELOPMENT_TYPES = {"DEVELOPMENT", "IOS_DEVELOPMENT"}


def token():
    with open(os.environ["KEY_PATH"]) as f:
        key = f.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def call(method, url, auth):
    request = urllib.request.Request(url, method=method, headers={"Authorization": f"Bearer {auth}"})
    with urllib.request.urlopen(request, timeout=30) as response:
        body = response.read()
        return json.loads(body) if body else None


def main():
    auth = token()
    try:
        data = call("GET", f"{API}/certificates?limit=200", auth)
    except urllib.error.HTTPError as error:
        print(f"::warning::인증서 목록을 받지 못했습니다: HTTP {error.code} {error.read()[:300]!r}")
        return 0

    certificates = data.get("data", [])
    print(f"인증서 {len(certificates)}개")
    deleted = 0
    for cert in certificates:
        attributes = cert.get("attributes", {})
        name = attributes.get("name") or ""
        display = attributes.get("displayName") or ""
        kind = attributes.get("certificateType") or ""
        created_by_ci = "Created via API" in name or "Created via API" in display
        print(f"- {kind} | {name} | {display} | 만료 {attributes.get('expirationDate')} | {'CI' if created_by_ci else '유지'}")
        if kind in DEVELOPMENT_TYPES and created_by_ci:
            try:
                call("DELETE", f"{API}/certificates/{cert['id']}", auth)
                deleted += 1
            except urllib.error.HTTPError as error:
                print(f"::warning::{name} 삭제 실패: HTTP {error.code}")
    print(f"CI 개발 인증서 {deleted}개 삭제")
    return 0


if __name__ == "__main__":
    sys.exit(main())
