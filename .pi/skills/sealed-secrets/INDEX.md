# Sealed Secrets Skill - Index

Quick navigation guide for all components of the sealed-secrets skill.

## 🚀 Getting Started (Start Here!)

| File | Purpose | When to Use |
|------|---------|-------------|
| [QUICKSTART.md](QUICKSTART.md) | 30-second workflow guide | First time using the skill |
| [test-skill.sh](test-skill.sh) | Validate installation | After setup or updates |
| [examples/example-usage.sh](examples/example-usage.sh) | See it in action | Learning by example |

## 📖 Documentation

| File | Content | Audience |
|------|---------|----------|
| [SKILL.md](SKILL.md) | Agent Skills standard format | AI agents & developers |
| [README.md](README.md) | Quick reference | Developers (daily use) |
| [FEATURES.md](FEATURES.md) | Complete feature list | Technical evaluation |
| [MANIFEST.txt](MANIFEST.txt) | Production manifest | Ops & deployment |

## 🛠️ Scripts (Production Tools)

### Main Scripts

| Script | Purpose | Usage Pattern |
|--------|---------|---------------|
| [scripts/seal-secret.sh](scripts/seal-secret.sh) | Interactive/pipe secret sealer | `./seal-secret.sh` or `cat secret.yaml \| ./seal-secret.sh --stdin` |
| [scripts/quick-secrets.sh](scripts/quick-secrets.sh) | Quick generators for common types | `./quick-secrets.sh docker dockerhub media` |

### Script Capabilities Matrix

| Feature | seal-secret.sh | quick-secrets.sh |
|---------|----------------|------------------|
| Interactive prompts | ✅ | ✅ |
| Pipe mode | ✅ | ❌ |
| Password masking | ✅ | ✅ |
| Name validation | ✅ | ✅ |
| Custom cert path | ✅ | ❌ |
| Docker secrets | Via type menu | ✅ Dedicated |
| TLS secrets | Via type menu | ✅ Dedicated |
| Basic auth | Via type menu | ✅ Dedicated |
| SSH keys | Via type menu | ✅ Dedicated |
| File secrets | Via stdin | ✅ Dedicated |

## 🎯 Use Case Quick Reference

### "I need to create a..."

| Secret Type | Command |
|-------------|---------|
| Generic key-value pairs | `./scripts/seal-secret.sh` (choose type 1) |
| Docker Hub credentials | `./scripts/quick-secrets.sh docker` |
| TLS certificate | `./scripts/quick-secrets.sh tls` |
| Username/password | `./scripts/quick-secrets.sh basicauth` |
| SSH private key | `./scripts/quick-secrets.sh ssh` |
| Config from file | `./scripts/quick-secrets.sh file` |

### "I have a..."

| Starting Point | Solution |
|----------------|----------|
| Raw secret YAML file | `cat secret.yaml \| ./scripts/seal-secret.sh --stdin` |
| kubectl dry-run output | Pipe to `./scripts/seal-secret.sh --stdin` |
| Multiple key-value pairs | Interactive mode: `./scripts/seal-secret.sh` |
| Certificate files | `./scripts/quick-secrets.sh tls` |
| Config directory | `./scripts/quick-secrets.sh file` |

## 📊 File Structure

```
.pi/skills/sealed-secrets/
├── 📜 Core Scripts (scripts/)
│   ├── seal-secret.sh          250 lines │ Main sealer
│   └── quick-secrets.sh        180 lines │ Quick generators
│
├── 📚 Documentation (root)
│   ├── SKILL.md                160 lines │ Standard format
│   ├── README.md                60 lines │ Quick ref
│   ├── QUICKSTART.md           100 lines │ Fast start
│   ├── FEATURES.md             290 lines │ Feature list
│   ├── MANIFEST.txt            120 lines │ Production manifest
│   └── INDEX.md                (this)    │ Navigation guide
│
├── 📋 Examples (examples/)
│   └── example-usage.sh        110 lines │ Usage scenarios
│
├── 🧪 Testing (root)
│   └── test-skill.sh           140 lines │ Test suite
│
└── 🛡️ Safety (.gitignore)
    └── Patterns to prevent committing raw secrets
```

## 🔍 Quick Searches

### "How do I...?"

- **Create my first secret**: See [QUICKSTART.md](QUICKSTART.md) → 30-Second Workflow
- **Understand all features**: See [FEATURES.md](FEATURES.md)
- **See examples**: Run [examples/example-usage.sh](examples/example-usage.sh)
- **Validate setup**: Run [test-skill.sh](test-skill.sh)
- **Get help with a script**: Run script with `--help`

### "What can this do?"

- **Supported secret types**: See [FEATURES.md](FEATURES.md) → Supported Secret Types
- **Security model**: See [SKILL.md](SKILL.md) → Security Model
- **Integration points**: See [FEATURES.md](FEATURES.md) → Integration Points
- **Best practices**: See [SKILL.md](SKILL.md) → The Prime Directive

### "Something's wrong..."

- **Prerequisites missing**: Run [test-skill.sh](test-skill.sh) to diagnose
- **Certificate not found**: Check [SKILL.md](SKILL.md) → Troubleshooting
- **kubeseal errors**: See [SKILL.md](SKILL.md) → Troubleshooting
- **Name validation failed**: See [QUICKSTART.md](QUICKSTART.md) → Invalid name

## 📈 Learning Path

### Level 1: Beginner (First 10 minutes)
1. Read [QUICKSTART.md](QUICKSTART.md)
2. Run [test-skill.sh](test-skill.sh)
3. Try interactive mode: `./scripts/seal-secret.sh`

### Level 2: Intermediate (Next 20 minutes)
1. Try [examples/example-usage.sh](examples/example-usage.sh)
2. Create a Docker secret: `./scripts/quick-secrets.sh docker`
3. Pipe an existing secret: `cat secret.yaml | ./scripts/seal-secret.sh --stdin`

### Level 3: Advanced (Deep dive)
1. Read [FEATURES.md](FEATURES.md) for complete capabilities
2. Study [SKILL.md](SKILL.md) for security model
3. Review script source code for implementation details

## 🔗 External References

- **Sealed Secrets Project**: https://github.com/bitnami-labs/sealed-secrets
- **kubeseal Releases**: https://github.com/bitnami-labs/sealed-secrets/releases
- **OpenShift Docs**: https://docs.openshift.com/
- **Kubernetes Secrets**: https://kubernetes.io/docs/concepts/configuration/secret/

## 📞 Support Matrix

| Question Type | Reference |
|---------------|-----------|
| "How do I...?" | [QUICKSTART.md](QUICKSTART.md) |
| "What is...?" | [SKILL.md](SKILL.md) |
| "Can it...?" | [FEATURES.md](FEATURES.md) |
| "Why isn't...?" | [SKILL.md](SKILL.md) → Troubleshooting |
| "Show me..." | [examples/example-usage.sh](examples/example-usage.sh) |

## 🎯 Integration Checklist

Use this when integrating sealed-secrets into your workflow:

- [ ] Prerequisites installed (kubeseal, oc, certificate)
- [ ] Test suite passing (`./test-skill.sh`)
- [ ] First secret created successfully
- [ ] Committed to Git and synced via ArgoCD
- [ ] Verified decryption in cluster
- [ ] Team trained on usage
- [ ] Documentation bookmarked
- [ ] .gitignore patterns in place

## 🔄 Maintenance Schedule

| Task | Frequency | Reference |
|------|-----------|-----------|
| Update certificate | When controller key rotates | [MANIFEST.txt](MANIFEST.txt) → Maintainer Notes |
| Test after kubeseal upgrade | Each upgrade | [test-skill.sh](test-skill.sh) |
| Review examples | Monthly | [examples/example-usage.sh](examples/example-usage.sh) |
| Validate against cluster | Quarterly | [test-skill.sh](test-skill.sh) |

---

**Last Updated**: January 8, 2026  
**Version**: 1.0  
**Status**: Production Ready ✅
