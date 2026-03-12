# Runbook — site-kubectl

Guia operacional para diagnóstico e resolução de problemas comuns.

---

## Informações Gerais

| Campo | Valor |
|-------|-------|
| Aplicação | site-kubectl |
| Namespace | reliabilitylab |
| Porta | 8000 |
| Health check | GET /api/health |
| Imagem | local/reliabilitylab-site-kubectl:latest |

---

## Problema: Pod em CrashLoopBackOff

### Sintomas
- Pod reiniciando continuamente
- `kubectl get pods -n reliabilitylab` mostra status `CrashLoopBackOff`

### Diagnóstico

```bash
# Ver eventos do pod
kubectl describe pod -n reliabilitylab -l app.kubernetes.io/name=site-kubectl

# Ver logs do container
kubectl logs -n reliabilitylab -l app.kubernetes.io/name=site-kubectl --tail=50

# Ver logs do crash anterior
kubectl logs -n reliabilitylab -l app.kubernetes.io/name=site-kubectl --previous
```

### Causas Comuns

1. **Imagem não encontrada** → Verificar se a imagem foi carregada no cluster
2. **Porta já em uso** → Verificar `APP_PORT` no ConfigMap
3. **Erro de importação Python** → Verificar requirements.txt e rebuild da imagem
4. **Permissão negada** → Verificar se `runAsUser` é compatível com a imagem

### Resolução

```bash
# Rebuild e reimportar a imagem
make build
make load-kind   # ou load-k3d ou load-minikube

# Reiniciar o deployment
make restart
```

---

## Problema: Ingress não responde

### Sintomas
- `curl http://site-kubectl.local` retorna erro de conexão
- Timeout ao acessar no navegador

### Diagnóstico

```bash
# Verificar se o Ingress Controller está rodando
kubectl get pods -n ingress-nginx

# Verificar o recurso Ingress
kubectl get ingress -n reliabilitylab
kubectl describe ingress site-kubectl -n reliabilitylab

# Verificar se o Service tem endpoints
kubectl get endpoints site-kubectl -n reliabilitylab
```

### Causas Comuns

1. **Ingress Controller não instalado** → Instalar NGINX Ingress Controller
2. **/etc/hosts não configurado** → Adicionar entrada para `site-kubectl.local`
3. **Service sem endpoints** → Pods não estão prontos (verificar probes)
4. **IngressClass inexistente** → Verificar `ingressClassName: nginx`

### Resolução

```bash
# Instalar ingress controller (kind)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Instalar ingress controller (minikube)
minikube addons enable ingress

# Descobrir IP e atualizar /etc/hosts
# kind/k3d: geralmente 127.0.0.1
# minikube: usar $(minikube ip)
echo "127.0.0.1 site-kubectl.local" | sudo tee -a /etc/hosts
```

---

## Problema: HPA não escala

### Sintomas
- `kubectl get hpa -n reliabilitylab` mostra targets como `<unknown>`
- Pods não escalam mesmo sob carga

### Diagnóstico

```bash
# Verificar status do HPA
kubectl get hpa -n reliabilitylab
kubectl describe hpa site-kubectl -n reliabilitylab

# Verificar se o metrics-server está rodando
kubectl get pods -n kube-system | grep metrics-server
kubectl top pods -n reliabilitylab
```

### Causas Comuns

1. **metrics-server não instalado** → Instalar metrics-server
2. **Recursos não definidos** → Pods precisam de `requests` para CPU/memória
3. **Pods insuficientes** → Verificar `minReplicas`

### Resolução

```bash
# Instalar metrics-server (kind/k3d)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Instalar metrics-server (minikube)
minikube addons enable metrics-server

# Verificar após instalação
kubectl top pods -n reliabilitylab
```

---

## Problema: Logs não aparecem no Loki/Grafana

### Sintomas
- Dashboard do Grafana sem dados de log
- Queries no Loki retornam vazias

### Diagnóstico

```bash
# Verificar se Promtail está rodando
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail

# Verificar logs do Promtail
kubectl logs -n monitoring -l app.kubernetes.io/name=promtail --tail=20

# Verificar se Loki está acessível
kubectl get svc -n monitoring | grep loki
```

### Resolução

```bash
# Reinstalar Promtail
helm upgrade --install promtail grafana/promtail \
  -n monitoring -f observability/loki/promtail-values.yaml

# Verificar conectividade
kubectl exec -n monitoring deploy/promtail -- wget -qO- http://loki:3100/ready
```

---

## Comandos Úteis de Operação

```bash
# Status geral do namespace
kubectl get all -n reliabilitylab

# Acompanhar logs em tempo real
make logs

# Reiniciar deployment sem downtime
make restart

# Verificar saúde da aplicação
kubectl exec -n reliabilitylab deploy/site-kubectl -- \
  python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8000/api/health').read().decode())"

# Port-forward direto para debug
kubectl port-forward -n reliabilitylab svc/site-kubectl 8000:80

# Verificar recursos consumidos
kubectl top pods -n reliabilitylab
kubectl top nodes
```
