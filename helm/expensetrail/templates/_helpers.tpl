{{- define "et.image" -}}
{{- $reg := .root.Values.image.registry -}}
{{- if $reg -}}{{ $reg }}/{{ .name }}:{{ .root.Values.image.tag }}{{- else -}}{{ .name }}:{{ .root.Values.image.tag }}{{- end -}}
{{- end -}}

{{- define "et.labels" -}}
app.kubernetes.io/part-of: expensetrail
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}
