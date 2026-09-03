# Deploy each VM with its ansible playbook (run from the repo root).
# The root ansible.cfg supplies the SSH key and host-key-checking settings.

ANSIBLE_PLAYBOOK ?= ansible-playbook
TFVARS           ?= proxmox.tfvars

# Read a quoted string variable from $(TFVARS), e.g. $(call tfvar,jenkins_admin_password)
tfvar = $(shell grep -E '^$1[[:space:]]*=' $(TFVARS) | head -n1 | sed -E 's/^[^=]*=[[:space:]]*"?([^"]*)"?.*/\1/')

.PHONY: deploy-llm deploy-llm-observability deploy-jenkins deploy-jenkins-agent deploy-open-webui deploy-postgres deploy-monitoring deploy-elk deploy-dns deploy-exporters

# All IPs come from $(TFVARS): the inventory files no longer carry
# ansible_host, so every target passes it via --extra-vars.

deploy-llm:
	$(ANSIBLE_PLAYBOOK) -i modules/llm/inventory.ini modules/llm/ansible.yml \
		--extra-vars "ansible_host=$(call tfvar,llm_ip)"

# Request-plane observability on the LLM VM (nginx JSON access log + Filebeat
# shipper to the ELK VM). Standalone on purpose: rolls out WITHOUT the
# disruptive full deploy-llm run. Requires the ELK VM to be up.
deploy-llm-observability:
	$(ANSIBLE_PLAYBOOK) -i modules/llm/inventory.ini modules/llm/observability.yml \
		--extra-vars "ansible_host=$(call tfvar,llm_ip) es_host=$(call tfvar,elk_ip)"

deploy-vllm:
	$(ANSIBLE_PLAYBOOK) -i modules/llm/inventory.ini modules/llm/vllm.yml \
		--extra-vars "ansible_host=$(call tfvar,llm_ip)"

deploy-jenkins:
	$(ANSIBLE_PLAYBOOK) -i modules/jenkins/inventory.ini modules/jenkins/ansible.yml \
		--extra-vars "jenkins_admin_password=$(call tfvar,jenkins_admin_password) \
		ansible_host=$(call tfvar,jenkins_ip) \
		jenkins_http_host=$(call tfvar,jenkins_ip) \
		jenkins_agent_host=$(call tfvar,jenkins_agent_ip)"

deploy-jenkins-agent:
	$(ANSIBLE_PLAYBOOK) -i modules/jenkins-agent/inventory.ini modules/jenkins-agent/ansible.yml \
		--extra-vars "ansible_host=$(call tfvar,jenkins_agent_ip)"

deploy-open-webui:
	$(ANSIBLE_PLAYBOOK) -i modules/open-webui/inventory.ini modules/open-webui/ansible.yml \
		--extra-vars "ansible_host=$(call tfvar,open_webui_ip) \
		webui_ip=$(call tfvar,open_webui_ip) \
		llm_ip=$(call tfvar,llm_ip)"

deploy-postgres:
	$(ANSIBLE_PLAYBOOK) -i modules/postgres/inventory.ini modules/postgres/ansible.yml \
		--extra-vars "postgres_password=$(call tfvar,postgres_password) \
		smartshift_admin_password=$(call tfvar,smartshift_admin_password) \
		analytics_ro_password=$(call tfvar,analytics_ro_password) \
		ansible_host=$(call tfvar,postgres_ip) \
		lan_network=$(call tfvar,lan_network)"

# Monitoring VM (Prometheus + Grafana + blackbox). Also runs automatically
# via the Terraform action trigger when the VM is created or updated.
deploy-monitoring:
	$(ANSIBLE_PLAYBOOK) -i modules/monitoring/inventory.ini modules/monitoring/ansible.yml \
		--extra-vars "grafana_admin_password=$(call tfvar,grafana_admin_password) \
		ansible_host=$(call tfvar,monitoring_ip) \
		llm_ip=$(call tfvar,llm_ip) \
		jenkins_ip=$(call tfvar,jenkins_ip) \
		jenkins_agent_ip=$(call tfvar,jenkins_agent_ip) \
		open_webui_ip=$(call tfvar,open_webui_ip) \
		postgres_ip=$(call tfvar,postgres_ip) \
		elk_ip=$(call tfvar,elk_ip)"

# ELK VM (Elasticsearch + Kibana). Also runs automatically
# via the Terraform action trigger when the VM is created or updated.
deploy-elk:
	$(ANSIBLE_PLAYBOOK) -i modules/elk/inventory.ini modules/elk/ansible.yml \
		--extra-vars "ansible_host=$(call tfvar,elk_ip)"

# DNS VM (dnsmasq, *.lan records + DoT upstreams). Also runs automatically
# via the Terraform action trigger when the VM is created or updated.
deploy-dns:
	$(ANSIBLE_PLAYBOOK) -i modules/dns/inventory.ini modules/dns/ansible.yml \
		--extra-vars "ansible_host=$(call tfvar,dns_ip) \
		dns_ip=$(call tfvar,dns_ip) \
		pve_ip=$(call tfvar,pve_ip) \
		llm_ip=$(call tfvar,llm_ip) \
		jenkins_ip=$(call tfvar,jenkins_ip) \
		jenkins_agent_ip=$(call tfvar,jenkins_agent_ip) \
		open_webui_ip=$(call tfvar,open_webui_ip) \
		postgres_ip=$(call tfvar,postgres_ip) \
		monitoring_ip=$(call tfvar,monitoring_ip) \
		elk_ip=$(call tfvar,elk_ip) \
		lan_gateway=$(call tfvar,lan_gateway)"

# Scrape targets on the VMs (node_exporter, GPU collector, postgres_exporter,
# Jenkins prometheus plugin). Idempotent — run after the service playbooks.
# The play is multi-host, but Ansible extra vars are global and inventory
# values cannot be templated, so the playbook runs once per host group.
deploy-exporters:
	@for entry in \
		"llm $(call tfvar,llm_ip)" \
		"jenkins $(call tfvar,jenkins_ip)" \
		"jenkins-agent $(call tfvar,jenkins_agent_ip)" \
		"open-webui $(call tfvar,open_webui_ip)" \
		"postgres $(call tfvar,postgres_ip)" \
		"elk $(call tfvar,elk_ip)"; do \
		group=$${entry%% *}; ip=$${entry##* }; \
		$(ANSIBLE_PLAYBOOK) -i modules/monitoring/inventory.ini --limit "$$group" modules/monitoring/exporters.yml \
		--extra-vars "ansible_host=$$ip jenkins_admin_password=$(call tfvar,jenkins_admin_password) postgres_password=$(call tfvar,postgres_password)"; \
	done
