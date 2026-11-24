"""Conversation loop over the Bedrock Converse API; the model sees only sanitised, compressed, wrapped tool results."""
from pathlib import Path

from .compress import clean

PROMPT = Path(__file__).with_name("prompt.md")


class Session:
    def __init__(self, client, model_id, tools, redactor, cfg, budget_tokens, transcript=None):
        self.client, self.model_id, self.tools, self.redactor, self.cfg = client, model_id, tools, redactor, cfg
        self.budget_tokens = budget_tokens
        self.used_tokens = 0
        self.transcript = transcript
        self.messages = []
        self.system = [{"text": PROMPT.read_text(encoding="utf-8")}]

    def _log(self, role, text):
        if self.transcript:
            self.transcript(self.redactor.redact(f"{role}: {text}"))

    def ask(self, question):
        """Returns the final answer, sanitised again; the question is redacted before it is sent."""
        question = self.redactor.redact(question)
        self._log("admin", question)
        self.messages.append({"role": "user", "content": [{"text": question}]})
        b = self.cfg["bedrock"]
        for _ in range(self.cfg["limits"]["max_turns"]):
            if self.used_tokens >= self.budget_tokens:
                return self._finish(f"[session token budget of {self.budget_tokens} reached; stopping]")
            kw = {}
            if b.get("guardrail_id") and b.get("guardrail_version"):
                kw["guardrailConfig"] = {"guardrailIdentifier": b["guardrail_id"], "guardrailVersion": str(b["guardrail_version"]), "trace": "disabled"}
            resp = self.client.converse(modelId=self.model_id, system=self.system, messages=self.messages,
                                        toolConfig=self.tools.bedrock_tool_config(),
                                        inferenceConfig={"maxTokens": b["max_output_tokens"], "temperature": b["temperature"]}, **kw)
            usage = resp.get("usage") or {}
            self.used_tokens += int(usage.get("inputTokens", 0)) + int(usage.get("outputTokens", 0))
            message = resp["output"]["message"]
            self.messages.append(message)
            uses = [c["toolUse"] for c in message["content"] if "toolUse" in c]
            if not uses:
                return self._finish("\n".join(c["text"] for c in message["content"] if "text" in c))
            results = []
            for u in uses:
                out = self.tools.call(u.get("name"), u.get("input"))
                self._log(f"tool:{u.get('name')}", out)
                results.append({"toolResult": {"toolUseId": u["toolUseId"], "content": [{"text": out}]}})
            self.messages.append({"role": "user", "content": results})
        return self._finish("[turn limit reached; stopping]")

    def _finish(self, text):
        text = clean(self.redactor.redact(clean(text)))
        self._log("agent", text)
        return text

