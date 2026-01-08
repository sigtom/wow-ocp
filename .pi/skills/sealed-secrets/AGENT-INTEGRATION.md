# Agent Integration Guide

## ✅ Skill Is Ready for Pi Coding Agent

The `sealed-secrets` skill is properly configured and will be automatically discovered by the pi-coding-agent.

## How It Works

### 1. **Automatic Discovery**

Pi scans for skills in these locations (your skill is in #5):

1. `~/.codex/skills/**/SKILL.md` (Codex CLI)
2. `~/.claude/skills/*/SKILL.md` (Claude Code user)
3. `<cwd>/.claude/skills/*/SKILL.md` (Claude Code project)
4. `~/.pi/agent/skills/**/SKILL.md` (Pi user)
5. **`<cwd>/.pi/skills/**/SKILL.md`** ← **Your skill is here!** ✅

### 2. **Skill Registration**

When pi starts in `/home/sigtom/wow-ocp`, it will:
- Find `.pi/skills/sealed-secrets/SKILL.md`
- Extract the frontmatter:
  ```yaml
  name: sealed-secrets
  description: Create sealed secrets for OpenShift using Bitnami Sealed Secrets...
  ```
- Add it to the available skills list

### 3. **Skill Loading (On-Demand)**

The skill loads when:
- **Agent decides**: Task matches the description (keywords: "sealed secret", "kubeseal", "encrypt secret", "seal secret")
- **User requests**: You explicitly say "use the sealed-secrets skill"
- **Related task**: You mention creating/sealing secrets for OpenShift

### 4. **Agent Uses the Skill**

When loaded, the agent will:
1. Read the full `SKILL.md` content
2. Follow the instructions and workflows
3. Use the scripts with relative paths:
   - `{baseDir}/scripts/seal-secret.sh`
   - `{baseDir}/scripts/quick-secrets.sh`
4. Reference documentation files as needed

## Verification

### Check Skill Discovery

```bash
# Start pi in your project directory
cd /home/sigtom/wow-ocp
pi

# In the chat, ask:
"What skills do you have available?"

# Or specifically:
"Do you have a sealed-secrets skill?"
```

### Test Skill Activation

Try any of these prompts:

```
"I need to create a sealed secret for my Plex claim token"

"Help me seal a Docker Hub credentials secret"

"Use the sealed-secrets skill to create a TLS certificate secret"

"How do I securely store secrets in Git for my OpenShift cluster?"
```

The agent should:
1. Recognize the task matches the sealed-secrets skill
2. Load the skill (you might see it reference SKILL.md)
3. Follow the workflows in the documentation
4. Suggest using the scripts

## What the Agent Sees

### In System Prompt (Always Available)

```xml
<available_skills>
  <skill>
    <name>sealed-secrets</name>
    <description>Create sealed secrets for OpenShift using Bitnami Sealed Secrets. Interactive workflow for securely encrypting secrets with kubeseal before committing to Git.</description>
    <location>/home/sigtom/wow-ocp/.pi/skills/sealed-secrets/SKILL.md</location>
  </skill>
  <!-- other skills... -->
</available_skills>
```

### When Task Matches (Loaded On-Demand)

The agent uses the `read` tool to load:
```
/home/sigtom/wow-ocp/.pi/skills/sealed-secrets/SKILL.md
```

Then follows the instructions, referencing:
- Setup steps
- Usage patterns
- Script paths (replaced with absolute paths)
- Examples and workflows

## Advanced Configuration

### Settings File (Optional)

Create `~/.pi/agent/settings.json` to customize:

```json
{
  "skills": {
    "enabled": true,
    "enablePiProject": true,
    "includeSkills": ["sealed-secrets"]
  }
}
```

### CLI Override (Optional)

Load only specific skills for a session:

```bash
# Only load sealed-secrets
pi --skills sealed-secrets

# Load sealed-secrets and other skills
pi --skills "sealed-secrets,brave-search"
```

### Disable Skill (Temporary)

```bash
# Run without any skills
pi --no-skills

# Or disable in settings.json
{
  "skills": {
    "enabled": false
  }
}
```

## Troubleshooting

### "Skill not found"

**Check discovery:**
```bash
cd /home/sigtom/wow-ocp
ls -la .pi/skills/sealed-secrets/SKILL.md
```

**Verify frontmatter:**
```bash
head -5 .pi/skills/sealed-secrets/SKILL.md
```

Must have:
```yaml
---
name: sealed-secrets
description: ...
---
```

**Check name matches directory:**
```bash
# Directory name
basename .pi/skills/sealed-secrets
# Should output: sealed-secrets

# Frontmatter name (should match)
grep "^name:" .pi/skills/sealed-secrets/SKILL.md
# Should output: name: sealed-secrets
```

### "Scripts not working"

The agent uses relative paths, so ensure you're in the project root:
```bash
cd /home/sigtom/wow-ocp
pi
```

### "Agent not using the skill"

Try being more explicit:
```
"Use the sealed-secrets skill to help me create a secret for my Plex server"
```

Or check if skills are enabled:
```bash
pi --skills sealed-secrets
```

## Example Agent Interactions

### Example 1: Simple Request

**You:** "I need to create a sealed secret for my Docker Hub credentials"

**Agent:**
1. Recognizes task matches sealed-secrets skill
2. Loads SKILL.md
3. Suggests: "I'll help you create a sealed Docker Hub secret. Use the quick-secrets script..."
4. Provides command: `.pi/skills/sealed-secrets/scripts/quick-secrets.sh docker`

### Example 2: Explicit Request

**You:** "Use the sealed-secrets skill"

**Agent:**
1. Loads the skill
2. Shows available options (interactive, quick generators, pipe mode)
3. Asks what type of secret you need

### Example 3: Implicit Match

**You:** "How do I store API keys safely in Git for my OpenShift apps?"

**Agent:**
1. Recognizes this matches sealed-secrets description
2. Loads the skill
3. Explains the security model
4. Walks through the workflow

## Best Practices

### For Users

1. **Be in project root**: Always run `pi` from `/home/sigtom/wow-ocp`
2. **Use keywords**: Mention "sealed secret", "kubeseal", "encrypt secret"
3. **Be explicit if needed**: Say "use the sealed-secrets skill"

### For Agent

When the skill is loaded:
1. **Always reference scripts with full paths** from the skill base
2. **Suggest running from project root** (`cd /home/sigtom/wow-ocp`)
3. **Mention test suite** for verification
4. **Remind about security**: Never commit raw secrets

## Validation

Run this to verify the skill is properly configured:

```bash
cd /home/sigtom/wow-ocp
.pi/skills/sealed-secrets/test-skill.sh
```

All 17 tests should pass ✅

## Summary

✅ **Skill Location**: `/home/sigtom/wow-ocp/.pi/skills/sealed-secrets/`  
✅ **Discoverable**: Yes (Pi project skills)  
✅ **Valid Name**: `sealed-secrets` matches directory  
✅ **Valid Description**: Specific and actionable  
✅ **Scripts Executable**: All scripts have +x permission  
✅ **Documentation Complete**: SKILL.md follows standard  
✅ **Tests Passing**: 17/17 tests pass  

**Status: Ready for Production Use** 🚀

The skill will automatically be available next time you run `pi` in this directory!

---

**Quick Test:**
```bash
cd /home/sigtom/wow-ocp
pi
# Then ask: "What sealed-secrets capabilities do you have?"
```
