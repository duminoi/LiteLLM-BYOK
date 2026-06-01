#!/usr/bin/env python3
"""
patch-litellm.py - Tu dong apply 2 patches can thiet cho LiteLLM
de cac model trong OpenCode Go (qwen, kimi, deepseek,...) hoat dong
qua endpoint /v1/responses.

PATCH 1: Fix empty tools list bi Alibaba upstream reject voi "[] is too short"
PATCH 2: Fix non-function tools bi pass-through khong wrap function{}

Script nay IDEMPOTENT - chay nhieu lan chi patch 1 lan. Neu LiteLLM
thay doi source code va marker khong khop, script se bao loi.

Usage:
    python patch-litellm.py
"""
import sys
import io
import os

if sys.platform == "win32":
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

TRANSFORMATION_FILE = (
    r"C:\Users\ADMIN\AppData\Local\Programs\Python\Python312\Lib\site-packages"
    r"\litellm\responses\litellm_completion_transformation\transformation.py"
)

# Moi patch: (ten, marker_original, replacement, marker_da_patch)
PATCHES = [
    (
        "PATCH 1: Empty tools list (Alibaba reject `[] is too short`)",
        '            "tools": tools,\n            "top_p":',
        '            "tools": tools if tools else None,\n            "top_p":',
        '            "tools": tools if tools else None,\n            "top_p":',
    ),
    (
        "PATCH 2: Non-function tool conversion (Alibaba reject `tools.N` missing function)",
        '''            else:
                chat_completion_tools.append(
                    cast(Union[ChatCompletionToolParam, OpenAIMcpServerTool], tool)
                )''',
        '''            elif isinstance(tool, dict) and any(
                k in tool for k in ["name", "description", "parameters", "strict"]
            ):
                fn_fields = {}
                for k in ["name", "description", "parameters", "strict"]:
                    if k in tool:
                        fn_fields[k] = tool[k]
                if "parameters" not in fn_fields or not fn_fields["parameters"]:
                    fn_fields["parameters"] = {"type": "object"}
                converted = {"type": "function", "function": fn_fields}
                chat_completion_tools.append(cast(ChatCompletionToolParam, converted))''',
        '''            elif isinstance(tool, dict) and any(
                k in tool for k in ["name", "description", "parameters", "strict"]
            ):''',
    ),
]


def main():
    print("=" * 70)
    print("LiteLLM Patch Script")
    print("=" * 70)

    if not os.path.exists(TRANSFORMATION_FILE):
        print(f"ERROR: Khong tim thay file:\n  {TRANSFORMATION_FILE}")
        print("Hay kiem tra Python installation path.")
        sys.exit(1)

    with open(TRANSFORMATION_FILE, "r", encoding="utf-8") as f:
        content = f.read()

    print(f"File:  {TRANSFORMATION_FILE}")
    print(f"Size:  {len(content):,} bytes\n")

    applied = skipped = errored = 0

    for name, marker, replacement, already in PATCHES:
        if marker in content:
            new_content = content.replace(marker, replacement, 1)
            with open(TRANSFORMATION_FILE, "w", encoding="utf-8") as f:
                f.write(new_content)
            content = new_content
            print(f"  [APPLIED] {name}")
            applied += 1
        elif already in content:
            print(f"  [SKIP]    {name}  (da patch truoc do)")
            skipped += 1
        else:
            print(f"  [ERROR]   {name}")
            print(f"            Marker khong khop - LiteLLM co the da thay doi source.")
            print(f"            Can update marker trong patch-litellm.py.")
            errored += 1

    print("\n" + "-" * 70)
    print(f"Summary: {applied} applied, {skipped} skipped, {errored} errors")

    if errored:
        sys.exit(1)
    print("\nOK - LiteLLM da duoc patch. Co the khoi dong proxy.")


if __name__ == "__main__":
    main()
