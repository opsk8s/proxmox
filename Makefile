# Deploy each VM with its ansible playbook (run from the repo root).
# The root ansible.cfg supplies the SSH key and host-key-checking settings.

ANSIBLE_PLAYBOOK ?= ansible-playbook
TFVARS           ?= proxmox.tfvars

# Read a quoted string variable from $(TFVARS), e.g. $(call tfvar,jenkins_admin_password)
tfvar = $(shell grep -E '^$1[[:space:]]*=' $(TFVARS) | head -n1 | sed -E 's/^[^=]*=[[:space:]]*"?([^"]*)"?.*/\1/')

.PHONY: deploy-all deploy-llm deploy-jenkins deploy-jenkins-agent deploy-open-webui deploy-postgres deploy-taiga deploy-monitoring deploy-elk deploy-dns deploy-nginx deploy-exporters deploy-exporter

# All IPs come from $(TFVARS): the inventory files no longer carry
# ansible_host, so every target passes it via --extra-vars.

# Deploy every service in dependency order, sequentially, stopping on the
# first failure: dns (foundation) -> elk (hard prereq: deploy-nginx
# wait_for es:9200) -> independent backends -> nginx (gateway: deploy-
# open-webui fetches the LAN CA from it and verifies app.llm.lan over TLS)
# -> open-webui -> observability (monitoring, exporters).
# Run as: make deploy   (do NOT pass -j: prerequisite order is not -j-safe).
deploy-all: deploy-dns deploy-elk deploy-postgres deploy-taiga deploy-llm deploy-jenkins \
	deploy-jenkins-agent deploy-nginx deploy-open-webui \
	deploy-monitoring

deploy-llm:
	$(ANSIBLE_PLAYBOOK) -i modules/llm/inventory.ini modules/llm/ansible.yml \
		--extra-vars "ansible_host=$(call tfvar,llm_ip)"

deploy-vllm:
	$(ANSIBLE_PLAYBOOK) -i modules/llm/inventory.ini modules/llm/vllm.yml \
		--extra-vars "ansible_host=$(call tfvar,llm_ip)"

deploy-jenkins:
	$(ANSIBLE_PLAYBOOK) -i modules/jenkins/inventory.ini modules/jenkins/ansible.yml \
		--extra-vars "jenkins_admin_password=$(call tfvar,jenkins_admin_password) \
		jenkins_admin_email=$(call tfvar,jenkins_admin_email) \
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
		llm_ip=$(call tfvar,llm_ip) \
		nginx_ip=$(call tfvar,nginx_ip) \
		lan_ca_token=$(call tfvar,lan_ca_token)"

deploy-postgres:
	$(ANSIBLE_PLAYBOOK) -i modules/postgres/inventory.ini modules/postgres/ansible.yml \
		--extra-vars "postgres_password=$(call tfvar,postgres_password) \
		smartshift_admin_password=$(call tfvar,smartshift_admin_password) \
		analytics_ro_password=$(call tfvar,analytics_ro_password) \
		taiga_db_password=$(call tfvar,taiga_db_password) \
		ansible_host=$(call tfvar,postgres_ip) \
		lan_network=$(call tfvar,lan_network)"

# Taiga (project management) on the taiga VM: native install (gunicorn back,
# celery worker, node events, protected media, static server, local rabbitmq)
# against the shared postgres VM; the app.taiga.lan routing lives in the
# central nginx module (deploy-nginx).
# Requires deploy-postgres first (database + user). Also runs automatically
# via the Terraform action trigger when the VM is created or updated.
deploy-taiga:
	$(ANSIBLE_PLAYBOOK) -i modules/taiga/inventory.ini modules/taiga/ansible.yml \
		--extra-vars "taiga_db_password=$(call tfvar,taiga_db_password) \
		taiga_admin_password=$(call tfvar,taiga_admin_password) \
		postgres_ip=$(call tfvar,postgres_ip) \
		ansible_host=$(call tfvar,taiga_ip)"

# Monitoring VM (Prometheus + Grafana + blackbox). Also runs automatically
# via the Terraform action trigger when the VM is created or updated.
deploy-monitoring:
	$(ANSIBLE_PLAYBOOK) -i modules/monitoring/inventory.ini modules/monitoring/ansible.yml \
		--extra-vars "grafana_admin_password=$(call tfvar,grafana_admin_password) \
		jenkins_admin_password=$(call tfvar,jenkins_admin_password) \
		ansible_host=$(call tfvar,monitoring_ip) \
		dns_ip=$(call tfvar,dns_ip) \
		llm_ip=$(call tfvar,llm_ip) \
		jenkins_ip=$(call tfvar,jenkins_ip) \
		jenkins_agent_ip=$(call tfvar,jenkins_agent_ip) \
		open_webui_ip=$(call tfvar,open_webui_ip) \
		postgres_ip=$(call tfvar,postgres_ip) \
		elk_ip=$(call tfvar,elk_ip) \
		nginx_ip=$(call tfvar,nginx_ip) \
		taiga_ip=$(call tfvar,taiga_ip)"

# ELK VM (OpenSearch + Dashboards). Also runs automatically
# via the Terraform action trigger when the VM is created or updated.
deploy-elk:
	$(ANSIBLE_PLAYBOOK) -i modules/elk/inventory.ini modules/elk/ansible.yml \
		--extra-vars "ansible_host=$(call tfvar,elk_ip) es_ip=$(call tfvar,elk_ip)"

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
		taiga_ip=$(call tfvar,taiga_ip) \
		monitoring_ip=$(call tfvar,monitoring_ip) \
		elk_ip=$(call tfvar,elk_ip) \
		nginx_ip=$(call tfvar,nginx_ip) \
		lan_gateway=$(call tfvar,lan_gateway)"

# Reverse-proxy VM (nginx, vhosts for every service, JSON access log shipped
# by Filebeat to the ELK VM). Also runs automatically
# via the Terraform action trigger when the VM is created or updated.
deploy-nginx:
	$(ANSIBLE_PLAYBOOK) -i modules/nginx/inventory.ini modules/nginx/ansible.yml \
		--extra-vars "ansible_host=$(call tfvar,nginx_ip) \
		elk_ip=$(call tfvar,elk_ip) \
		monitoring_ip=$(call tfvar,monitoring_ip) \
		jenkins_ip=$(call tfvar,jenkins_ip) \
		open_webui_ip=$(call tfvar,open_webui_ip) \
		llm_ip=$(call tfvar,llm_ip) \
		taiga_ip=$(call tfvar,taiga_ip) \
		lan_ca_token=$(call tfvar,lan_ca_token)"

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
		"elk $(call tfvar,elk_ip)" \
		"dns $(call tfvar,dns_ip)" \
		"nginx $(call tfvar,nginx_ip)" \
		"taiga $(call tfvar,taiga_ip)"; do \
		group=$${entry%% *}; ip=$${entry##* }; \
		$(ANSIBLE_PLAYBOOK) -i modules/monitoring/inventory.ini --limit "$$group" modules/monitoring/exporters.yml \
		--extra-vars "ansible_host=$$ip jenkins_admin_password=$(call tfvar,jenkins_admin_password) postgres_password=$(call tfvar,postgres_password)"; \
	done

# Deploy exporters on a single host: make deploy-exporter HOST=taiga
deploy-exporter:
	@test -n "$(HOST)" || (echo "Usage: make deploy-exporter HOST=<group>" && exit 1)
	@host_var=$$(echo "$(HOST)" | tr '-' '_'); \
	ip=$$(grep -E "^$${host_var}_ip[[:space:]]*=" $(TFVARS) | head -n1 | sed -E 's/^[^=]*=[[:space:]]*"?([^"]*)"?.*/\1/'); \
	$(ANSIBLE_PLAYBOOK) -i modules/monitoring/inventory.ini --limit "$(HOST)" modules/monitoring/exporters.yml \
		--extra-vars "ansible_host=$$ip jenkins_admin_password=$(call tfvar,jenkins_admin_password) postgres_password=$(call tfvar,postgres_password)"
