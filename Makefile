# Deploy each VM with its ansible playbook (run from the repo root).
# The root ansible.cfg supplies the SSH key and host-key-checking settings.

ANSIBLE_PLAYBOOK ?= ansible-playbook
TFVARS           ?= proxmox.tfvars

# Read a quoted string variable from $(TFVARS), e.g. $(call tfvar,jenkins_admin_password)
tfvar = $(shell grep -E '^$1[[:space:]]*=' $(TFVARS) | head -n1 | sed -E 's/^[^=]*=[[:space:]]*"?([^"]*)"?.*/\1/')

.PHONY: deploy-llm deploy-jenkins deploy-jenkins-agent deploy-open-webui deploy-postgres deploy-monitoring deploy-exporters

deploy-llm:
	$(ANSIBLE_PLAYBOOK) -i modules/llm/inventory.ini modules/llm/ansible.yml

deploy-vllm:
	$(ANSIBLE_PLAYBOOK) -i modules/llm/inventory.ini modules/llm/vllm.yml

deploy-jenkins:
	$(ANSIBLE_PLAYBOOK) -i modules/jenkins/inventory.ini modules/jenkins/ansible.yml \
		--extra-vars "jenkins_admin_password=$(call tfvar,jenkins_admin_password)"

deploy-jenkins-agent:
	$(ANSIBLE_PLAYBOOK) -i modules/jenkins-agent/inventory.ini modules/jenkins-agent/ansible.yml

deploy-open-webui:
	$(ANSIBLE_PLAYBOOK) -i modules/open-webui/inventory.ini modules/open-webui/ansible.yml

deploy-postgres:
	$(ANSIBLE_PLAYBOOK) -i modules/postgres/inventory.ini modules/postgres/ansible.yml \
		--extra-vars "postgres_password=$(call tfvar,postgres_password)"

# Monitoring VM (Prometheus + Grafana + blackbox). Also runs automatically
# via the Terraform action trigger when the VM is created or updated.
deploy-monitoring:
	$(ANSIBLE_PLAYBOOK) -i modules/monitoring/inventory.ini modules/monitoring/ansible.yml \
		--extra-vars "grafana_admin_password=$(call tfvar,grafana_admin_password)"

# Scrape targets on the VMs (node_exporter, GPU collector, postgres_exporter,
# Jenkins prometheus plugin). Idempotent — run after the service playbooks.
deploy-exporters:
	$(ANSIBLE_PLAYBOOK) -i modules/monitoring/inventory.ini modules/monitoring/exporters.yml \
		--extra-vars "jenkins_admin_password=$(call tfvar,jenkins_admin_password) postgres_password=$(call tfvar,postgres_password)"
