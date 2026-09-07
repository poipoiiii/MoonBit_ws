///|
/// Embedded fallback web page served at "/".
fn index_html() -> String {
  "<!DOCTYPE html>" +
  "<html lang=\"zh-CN\">" +
  "<head>" +
  "<meta charset=\"UTF-8\">" +
  "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">" +
  "<title>AI Agent Runtime</title>" +
  "<style>" +
  "body { font-family: sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; background: #f5f5f5; }" +
  ".container { background: white; border-radius: 8px; padding: 20px; }" +
  "h1 { color: #333; text-align: center; }" +
  ".chat-box { border: 1px solid #ddd; border-radius: 8px; padding: 16px; height: 400px; overflow-y: auto; }" +
  ".message { margin: 8px 0; padding: 8px 12px; border-radius: 8px; }" +
  ".user-msg { background: #e3f2fd; text-align: right; }" +
  ".ai-msg { background: #f3e5f5; text-align: left; }" +
  ".input-area { display: flex; gap: 8px; }" +
  "input { flex: 1; padding: 10px; border: 1px solid #ddd; }" +
  "button { padding: 10px 20px; background: #7c3aed; color: white; border: none; cursor: pointer; }" +
  "button:hover { background: #6d28d9; }" +
  "</style>" +
  "</head>" +
  "<body>" +
  "<div class=\"container\">" +
  "<h1>AI Agent Runtime</h1>" +
  "<div class=\"chat-box\" id=\"chatBox\"></div>" +
  "<div class=\"input-area\">" +
  "<input type=\"text\" id=\"messageInput\" placeholder=\"Enter your message...\" />" +
  "<button onclick=\"sendMessage()\">Send</button>" +
  "</div>" +
  "<div class=\"status\" id=\"status\">Ready</div>" +
  "</div>" +
  "<script>" +
  "const chatBox = document.getElementById(\"chatBox\");" +
  "const status = document.getElementById(\"status\");" +
  "async function sendMessage() {" +
  "const input = document.getElementById(\"messageInput\");" +
  "const msg = input.value.trim(); if (!msg) return; input.value = \"\";" +
  "addMessage(msg, \"user-msg\");" +
  "status.textContent = \"Waiting...\";" +
  "try {" +
  "const resp = await fetch(\"/api/chat?message=\" + encodeURIComponent(msg));" +
  "const reader = resp.body.getReader();" +
  "const decoder = new TextDecoder();" +
  "while (true) { const { done, value } = await reader.read(); if (done) break;" +
  "const text = decoder.decode(value);" +
  "const lines = text.split(String.fromCharCode(10));" +
  "for (const line of lines) { if (line.startsWith(\"data: \")) {" +
  "addMessage(line.slice(6), \"ai-msg\");" +
  "} } }" +
  "} catch (e) { addMessage(\"Error: \" + e.message, \"ai-msg\"); }" +
  "}" +
  "function addMessage(text, cls) {" +
  "const div = document.createElement(\"div\");" +
  "div.className = \"message \" + cls;" +
  "div.textContent = text;" +
  "chatBox.appendChild(div);" +
  "}" +
  "</script>" +
  "</body>" +
  "</html>"
}
