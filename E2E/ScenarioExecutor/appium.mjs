const ELEMENT_KEY = "element-6066-11e4-a52e-4f735466cecf";

export class AppiumClient {
  constructor(baseUrl) {
    this.baseUrl = baseUrl.replace(/\/$/, "");
    this.sessionId = null;
  }

  async request(path, {method = "GET", body} = {}) {
    const response = await fetch(`${this.baseUrl}${path}`, {
      method,
      headers: body ? {"content-type": "application/json"} : undefined,
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(240_000),
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok || payload.value?.error) {
      const message = payload.value?.message ?? `${response.status} ${response.statusText}`;
      throw new Error(`Appium ${method} ${path}: ${message}`);
    }
    return payload.value;
  }

  async createSession() {
    const value = await this.request("/session", {
      method: "POST",
      body: {
        capabilities: {
          alwaysMatch: {
            platformName: "Mac",
            "appium:automationName": "Mac2",
            "appium:newCommandTimeout": 600,
            "appium:skipAppKill": true,
          },
        },
      },
    });
    this.sessionId = value.sessionId;
  }

  async deleteSession() {
    if (!this.sessionId) return;
    const sessionId = this.sessionId;
    this.sessionId = null;
    await this.request(`/session/${sessionId}`, {method: "DELETE"});
  }

  async execute(script, args = []) {
    return await this.request(`/session/${this.sessionId}/execute/sync`, {
      method: "POST",
      body: {script, args},
    });
  }

  async findElements(using, value, parentId = null) {
    const parent = parentId ? `/element/${parentId}` : "";
    const elements = await this.request(
      `/session/${this.sessionId}${parent}/elements`,
      {method: "POST", body: {using, value}},
    );
    return elements.map((element) => element[ELEMENT_KEY] ?? element.ELEMENT);
  }

  async elementRect(elementId) {
    return await this.request(
      `/session/${this.sessionId}/element/${elementId}/rect`,
    );
  }

  async elementAttribute(elementId, name) {
    return await this.request(
      `/session/${this.sessionId}/element/${elementId}/attribute/${encodeURIComponent(name)}`,
    );
  }

  async clickElement(elementId) {
    return await this.request(
      `/session/${this.sessionId}/element/${elementId}/click`,
      {method: "POST", body: {}},
    );
  }

  async source() {
    return await this.request(`/session/${this.sessionId}/source`);
  }
}
