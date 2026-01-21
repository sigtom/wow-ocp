import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";

export default function (pi: ExtensionAPI) {
  // --- Tool: nautobot_query ---
  pi.registerTool({
    name: "nautobot_query",
    label: "Nautobot Query",
    description: "Query Nautobot for device or virtual machine information by name.",
    parameters: Type.Object({
      name: Type.String({ description: "The name of the device or VM to search for" }),
      type: Type.Union([Type.Literal("device"), Type.Literal("vm")], { default: "vm" }),
    }),
    async execute(toolCallId, params, onUpdate, ctx, signal) {
      const endpoint = params.type === "vm" ? "virtualization/virtual-machines" : "dcim/devices";
      const token = process.env.NAUTOBOT_API_TOKEN;

      if (!token) {
        return { content: [{ type: "text", text: "Error: NAUTOBOT_API_TOKEN not found in environment." }] };
      }

      const url = `https://ipmgmt.sigtom.dev/api/${endpoint}/?name=${params.name}`;
      const res = await pi.exec("curl", ["-sk", "-H", `Authorization: Token ${token}`, url], { signal });

      if (res.code !== 0) {
        return { content: [{ type: "text", text: `Error calling Nautobot API: ${res.stderr}` }] };
      }

      return {
        content: [{ type: "text", text: res.stdout }],
        details: { raw: res.stdout },
      };
    },
  });

  // --- Tool: pve_status ---
  pi.registerTool({
    name: "pve_status",
    label: "Proxmox Status",
    description: "Check the status of a Virtual Machine or LXC on Proxmox.",
    parameters: Type.Object({
      vmid: Type.Integer({ description: "The Proxmox VMID" }),
      type: Type.Union([Type.Literal("qemu"), Type.Literal("lxc")], { default: "lxc" }),
      node: Type.String({ description: "The Proxmox node name", default: "wow-prox1" }),
    }),
    async execute(toolCallId, params, onUpdate, ctx, signal) {
      const token_secret = process.env.PROXMOX_SRE_BOT_API_TOKEN;
      const user = "sre-bot@pve";
      const token_id = "sre-token";

      if (!token_secret) {
        return { content: [{ type: "text", text: "Error: PROXMOX_SRE_BOT_API_TOKEN not found in environment." }] };
      }

      const url = `https://172.16.110.101:8006/api2/json/nodes/${params.node}/${params.type}/${params.vmid}/status/current`;
      const auth = `PVEAPIToken=${user}!${token_id}=${token_secret}`;
      const res = await pi.exec("curl", ["-sk", "-H", `Authorization: ${auth}`, url], { signal });

      if (res.code !== 0) {
        return { content: [{ type: "text", text: `Error calling Proxmox API: ${res.stderr}` }] };
      }

      return {
        content: [{ type: "text", text: res.stdout }],
        details: { raw: res.stdout },
      };
    },
  });

  // --- Tool: aap_launch ---
  pi.registerTool({
    name: "aap_launch",
    label: "AAP Launch",
    description: "Launch a Job Template in Ansible Automation Platform.",
    parameters: Type.Object({
      template_name: Type.String({ description: "The name of the Job Template" }),
      limit: Type.Optional(Type.String({ description: "Inventory limit (e.g., hostname)" })),
      extra_vars: Type.Optional(Type.Any({ description: "Extra variables for the job" })),
    }),
    async execute(toolCallId, params, onUpdate, ctx, signal) {
      const pass = process.env.CONTROLLER_PASSWORD;
      if (!pass) {
        return { content: [{ type: "text", text: "Error: CONTROLLER_PASSWORD not found in environment." }] };
      }

      // 1. Find the Template ID
      const listUrl = `https://aap.apps.ossus.sigtomtech.com/api/v2/job_templates/?name=${encodeURIComponent(params.template_name)}`;
      const listRes = await pi.exec("curl", ["-sk", "-u", `admin:${pass}`, listUrl], { signal });

      if (listRes.code !== 0) {
        return { content: [{ type: "text", text: `Error finding template: ${listRes.stderr}` }] };
      }

      const listData = JSON.parse(listRes.stdout);
      if (listData.count === 0) {
        return { content: [{ type: "text", text: `Error: Job Template '${params.template_name}' not found.` }] };
      }

      const templateId = listData.results[0].id;

      // 2. Launch the Template
      const launchUrl = `https://aap.apps.ossus.sigtomtech.com/api/v2/job_templates/${templateId}/launch/`;
      const payload: any = {};
      if (params.limit) payload.limit = params.limit;
      if (params.extra_vars) payload.extra_vars = params.extra_vars;

      const launchRes = await pi.exec("curl", [
        "-sk", "-u", `admin:${pass}`,
        "-X", "POST",
        "-H", "Content-Type: application/json",
        "-d", JSON.stringify(payload),
        launchUrl
      ], { signal });

      if (launchRes.code !== 0) {
        return { content: [{ type: "text", text: `Error launching template: ${launchRes.stderr}` }] };
      }

      return {
        content: [{ type: "text", text: `Job launched successfully: ${launchRes.stdout}` }],
        details: { raw: launchRes.stdout },
      };
    },
  });
}
