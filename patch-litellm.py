#!/usr/bin/env python3
"""
patch-litellm.py - Tu dong apply cac patches can thiet cho LiteLLM
de cac model trong OpenCode Go (qwen, kimi, deepseek,...) hoat dong
qua endpoint /v1/responses.

PATCH 1: Fix empty tools list bi Alibaba upstream reject voi "[] is too short"
PATCH 2: Fix non-function tools bi pass-through khong wrap function{}
PATCH 3: Fix tool_calls khong co tool message di kem (DeepSeek reject)
PATCH 4: Strip orphan tool_calls trong async_transform_request (gpt_transformation)
PATCH 5: Fix content=None -> content="" trong assistant function_call msg (Xiaomi reject)

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


def _find_litellm_file(relative_path):
    try:
        import litellm
        pkg_dir = os.path.dirname(litellm.__file__)
        candidate = os.path.join(pkg_dir, *relative_path.split("/"))
        if os.path.exists(candidate):
            return os.path.normpath(candidate)
    except ImportError:
        pass

    candidates = []
    if sys.platform == "win32":
        for base in [os.environ.get("PROGRAMFILES", "C:\\Program Files"),
                     os.environ.get("PROGRAMFILES(X86)", "C:\\Program Files (x86)"),
                     os.environ.get("LOCALAPPDATA", os.path.expanduser("~\\AppData\\Local"))]:
            candidates.append(os.path.join(base, "Python", "Lib", "site-packages",
                                            "litellm", *relative_path.split("/")))
            candidates.append(os.path.join(base, "Programs", "Python", "Lib", "site-packages",
                                            "litellm", *relative_path.split("/")))

    for c in candidates:
        if os.path.exists(c):
            return os.path.normpath(c)
    return None


TRANSFORMATION_FILE = _find_litellm_file("responses/litellm_completion_transformation/transformation.py")
UTILS_FILE = _find_litellm_file("utils.py")
GPT_TRANSFORMATION_FILE = _find_litellm_file("llms/openai/chat/gpt_transformation.py")

# Moi patch: (ten, file_path_func, marker_original, replacement, marker_da_patch)
PATCHES = [
    (
        "PATCH 1: Empty tools list (Alibaba reject `[] is too short`)",
        lambda: TRANSFORMATION_FILE,
        '            "tools": tools,\n            "top_p":',
        '            "tools": tools if tools else None,\n            "top_p":',
        '            "tools": tools if tools else None,\n            "top_p":',
    ),
    (
        "PATCH 2: Non-function tool conversion (Alibaba reject `tools.N` missing function)",
        lambda: TRANSFORMATION_FILE,
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
    (
        "PATCH 3: Strip orphan tool_calls not followed by tool message (DeepSeek reject - utils.py)",
        lambda: UTILS_FILE,
        '''def validate_and_fix_openai_messages(messages: List):
    """
    Ensures all messages are valid OpenAI chat completion messages.

    Handles missing role for assistant messages.
    """
    new_messages = []
    for message in messages:
        if not message.get("role"):
            message["role"] = "assistant"
        if message.get("tool_calls"):
            message["tool_calls"] = jsonify_tools(tools=message["tool_calls"])''',
        '''def validate_and_fix_openai_messages(messages: List):
    """
    Ensures all messages are valid OpenAI chat completion messages.

    Handles missing role for assistant messages.
    """
    new_messages = []
    for i, message in enumerate(messages):
        if not message.get("role"):
            message["role"] = "assistant"
        if message.get("tool_calls"):
            next_msg = messages[i + 1] if i + 1 < len(messages) else None
            has_tool_result = (
                next_msg is not None and next_msg.get("role") == "tool"
            )
            if has_tool_result:
                message["tool_calls"] = jsonify_tools(tools=message["tool_calls"])
            else:
                message.pop("tool_calls", None)''',
        '''def validate_and_fix_openai_messages(messages: List):
    """
    Ensures all messages are valid OpenAI chat completion messages.

    Handles missing role for assistant messages.
    """
    new_messages = []
    for i, message in enumerate(messages):''',
    ),
    (
        "PATCH 4: Strip orphan tool_calls AND orphan tool messages (DeepSeek reject - gpt_transformation base class)",
        lambda: GPT_TRANSFORMATION_FILE,
        '''        if self.__class__._is_base_class:
            return {
                "model": model,
                "messages": transformed_messages,
                **optional_params,
            }''',
        '''        if self.__class__._is_base_class:
            # Pass 1: Strip orphan tool_calls (assistant with tool_calls not
            # followed by a tool message). DeepSeek rejects these.
            for i in range(len(transformed_messages) - 1, -1, -1):
                msg = transformed_messages[i]
                if msg.get("tool_calls"):
                    next_msg = transformed_messages[i + 1] if i + 1 < len(transformed_messages) else {}
                    if next_msg.get("role") != "tool":
                        msg.pop("tool_calls", None)
                        if not msg.get("content"):
                            msg["content"] = ""
            # Pass 2: Remove orphan tool messages (tool message whose preceding
            # assistant had its tool_calls stripped above). DeepSeek rejects these.
            filtered = []
            for msg in transformed_messages:
                if msg.get("role") == "tool":
                    if not (filtered and filtered[-1].get("tool_calls")):
                        continue
                filtered.append(msg)
            transformed_messages = filtered
            return {
                "model": model,
                "messages": transformed_messages,
                **optional_params,
            }''',
        '''            # Pass 2: Remove orphan tool messages (tool message whose preceding''',
    ),
    (
        "PATCH 5: Assistant function_call content=None -> \"\" (Xiaomi/MiniMax reject empty assistant msg)",
        lambda: TRANSFORMATION_FILE,
        '''        # Create an assistant message with the tool call
        chat_completion_response_message = ChatCompletionResponseMessage(
            tool_calls=[tool_call],
            role="assistant",
            content=None,  # Function calls don't have content
        )''',
        '''        # Create an assistant message with the tool call
        # NOTE: content="" is required (not None) because some providers (Xiaomi/MiniMax)
        # reject assistant messages that have neither content nor tool_calls. If tool_calls
        # are later stripped (e.g. orphan tool_calls not followed by a tool message),
        # the message must still have content to satisfy strict providers.
        chat_completion_response_message = ChatCompletionResponseMessage(
            tool_calls=[tool_call],
            role="assistant",
            content="",
        )''',
        '''            content="",
        )''',
    ),
    (
        "PATCH 6: Strip orphan tool_calls AND tool messages in sync transform_request (DeepSeek reject - streaming path)",
        lambda: GPT_TRANSFORMATION_FILE,
        '''        optional_params.pop("max_retries", None)

        return {
            "model": model,
            "messages": messages,
            **optional_params,
        }''',
        '''        optional_params.pop("max_retries", None)

        # Pass 1: Strip orphan tool_calls (assistant with tool_calls not
        # followed by a tool message). DeepSeek rejects these.
        for i in range(len(messages) - 1, -1, -1):
            msg = messages[i]
            if msg.get("tool_calls"):
                next_msg = messages[i + 1] if i + 1 < len(messages) else {}
                if next_msg.get("role") != "tool":
                    msg.pop("tool_calls", None)
                    if not msg.get("content"):
                        msg["content"] = ""
        # Pass 2: Remove orphan tool messages (tool message whose preceding
        # assistant had its tool_calls stripped above). DeepSeek rejects these.
        filtered = []
        for msg in messages:
            if msg.get("role") == "tool":
                if not (filtered and filtered[-1].get("tool_calls")):
                    continue
            filtered.append(msg)
        messages = filtered

        return {
            "model": model,
            "messages": messages,
            **optional_params,
        }''',
        '''        # Pass 2: Remove orphan tool messages (tool message whose preceding''',
    ),
]


def main():
    print("=" * 70)
    print("LiteLLM Patch Script")
    print("=" * 70)

    applied = skipped = errored = 0

    for name, file_path_func, marker, replacement, already in PATCHES:
        file_path = file_path_func()
        if file_path is None or not os.path.exists(file_path):
            print(f"  [ERROR]   {name}")
            print(f"            Khong tim thay file target.")
            errored += 1
            continue

        with open(file_path, "r", encoding="utf-8") as f:
            content = f.read()

        print(f"  File: {file_path}")

        if marker in content:
            new_content = content.replace(marker, replacement, 1)
            with open(file_path, "w", encoding="utf-8") as f:
                f.write(new_content)
            content = new_content
            print(f"    [APPLIED] {name}")
            applied += 1
        elif already in content:
            print(f"    [SKIP]    {name}  (da patch truoc do)")
            skipped += 1
        else:
            print(f"    [ERROR]   {name}")
            print(f"              Marker khong khop - LiteLLM co the da thay doi source.")
            print(f"              Can update marker trong patch-litellm.py.")
            errored += 1

    print("\n" + "-" * 70)
    print(f"Summary: {applied} applied, {skipped} skipped, {errored} errors")

    if errored:
        sys.exit(1)
    print("\nOK - LiteLLM da duoc patch. Co the khoi dong proxy.")


if __name__ == "__main__":
    main()
