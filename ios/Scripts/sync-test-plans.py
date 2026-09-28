#!/usr/bin/env python3
"""把 XcodeGen 生成的 target ID 填进 Fast.xctestplan / Full.xctestplan。

测试计划按 ID 引用 target，而 .xcodeproj 每次都由 XcodeGen 重新生成、不进仓库。
这个脚本在 `xcodegen generate` 之后运行，按 target 名字找到 ID 写回两份计划；ID 没变就不改文件。
"""
import json
import re
import sys
from pathlib import Path

IOS_DIR = Path(__file__).resolve().parent.parent
PBXPROJ = IOS_DIR / "CalenEase.xcodeproj" / "project.pbxproj"
PLANS = [IOS_DIR / "Fast.xctestplan", IOS_DIR / "Full.xctestplan"]


def target_ids() -> dict[str, str]:
    text = PBXPROJ.read_text()
    pattern = re.compile(r"([0-9A-F]{24}) /\* ([^*]+?) \*/ = \{\s*isa = PBXNativeTarget;")
    return {name: ident for ident, name in pattern.findall(text)}


def fill(node, ids: dict[str, str], plan: Path) -> None:
    if isinstance(node, dict):
        if node.get("containerPath") == "container:CalenEase.xcodeproj" and "name" in node:
            if node["name"] not in ids:
                sys.exit(f"{plan.name}：工程里没有 target {node['name']}")
            node["identifier"] = ids[node["name"]]
        for value in node.values():
            fill(value, ids, plan)
    elif isinstance(node, list):
        for value in node:
            fill(value, ids, plan)


def main() -> None:
    ids = target_ids()
    for plan in PLANS:
        data = json.loads(plan.read_text())
        fill(data, ids, plan)
        text = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
        if text != plan.read_text():
            plan.write_text(text)
            print(f"更新了 {plan.name} 里的 target ID：" + "、".join(f"{name} {ids[name]}" for name in sorted(ids)))


if __name__ == "__main__":
    main()
