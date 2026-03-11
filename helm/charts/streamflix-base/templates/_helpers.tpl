{{- define "streamflix-base.name" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "streamflix-base.labels" -}}
app: {{ include "streamflix-base.name" . }}
app.kubernetes.io/name: {{ include "streamflix-base.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "streamflix-base.selectorLabels" -}}
app: {{ include "streamflix-base.name" . }}
{{- end }}
