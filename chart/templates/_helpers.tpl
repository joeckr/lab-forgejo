{{/*
Common labels for all resources
*/}}
{{- define "lab-forgejo.labels" -}}
app.kubernetes.io/part-of: {{ .Chart.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Forgejo selector labels
*/}}
{{- define "lab-forgejo.forgejo.selectorLabels" -}}
app.kubernetes.io/name: {{ .Values.forgejo.name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: {{ .Values.forgejo.name }}
{{- end }}

{{/*
PostgreSQL selector labels
*/}}
{{- define "lab-forgejo.postgres.selectorLabels" -}}
app.kubernetes.io/name: {{ .Values.postgres.name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: {{ .Values.postgres.name }}
{{- end }}

{{/*
Database host:port helper
*/}}
{{- define "lab-forgejo.dbHost" -}}
{{- if .Values.postgres.enabled -}}
{{ .Values.postgres.name }}:{{ .Values.postgres.port }}
{{- else -}}
{{ .Values.externalPostgres.host }}:{{ .Values.externalPostgres.port }}
{{- end -}}
{{- end }}

{{- define "lab-forgejo.dbHostOnly" -}}
{{- if .Values.postgres.enabled -}}
{{ .Values.postgres.name }}
{{- else -}}
{{ .Values.externalPostgres.host }}
{{- end -}}
{{- end }}

{{- define "lab-forgejo.dbPort" -}}
{{- if .Values.postgres.enabled -}}
{{ .Values.postgres.port }}
{{- else -}}
{{ .Values.externalPostgres.port }}
{{- end -}}
{{- end }}

{{- define "lab-forgejo.dbName" -}}
{{- if .Values.postgres.enabled -}}
{{ .Values.postgres.db }}
{{- else -}}
{{ .Values.externalPostgres.db }}
{{- end -}}
{{- end }}

{{- define "lab-forgejo.dbUser" -}}
{{- if .Values.postgres.enabled -}}
{{ .Values.postgres.user }}
{{- else -}}
{{ .Values.externalPostgres.user }}
{{- end -}}
{{- end }}

{{/*
Shared Forgejo environment variables (used by both initContainer and main container)
*/}}
{{- define "lab-forgejo.forgejo.env" -}}
- name: GITEA_WORK_DIR
  value: "/var/lib/gitea"
- name: GITEA_APP_INI
  value: "/etc/gitea/app.ini"
- name: FORGEJO_WORK_DIR
  value: "/var/lib/gitea"
- name: FORGEJO__DEFAULT__APP_NAME
  value: {{ .Values.forgejo.config.appName | quote }}
- name: FORGEJO__server__DOMAIN
  value: {{ .Values.forgejo.domain | quote }}
- name: FORGEJO__server__ROOT_URL
  value: {{ .Values.forgejo.rootUrl | quote }}
- name: FORGEJO__server__HTTP_PORT
  value: {{ .Values.forgejo.httpPort | quote }}
- name: FORGEJO__server__DISABLE_SSH
  value: {{ not .Values.forgejo.ssh.enabled | quote }}
{{- if .Values.forgejo.ssh.enabled }}
- name: FORGEJO__server__START_SSH_SERVER
  value: "true"
- name: FORGEJO__server__SSH_LISTEN_PORT
  value: {{ .Values.forgejo.ssh.port | quote }}
- name: FORGEJO__server__SSH_PORT
  value: {{ .Values.forgejo.ssh.servicePort | quote }}
{{- end }}
- name: FORGEJO__database__DB_TYPE
  value: "postgres"
- name: FORGEJO__database__HOST
  value: {{ include "lab-forgejo.dbHost" . | quote }}
- name: FORGEJO__database__NAME
  value: {{ include "lab-forgejo.dbName" . | quote }}
- name: FORGEJO__database__USER
  value: {{ include "lab-forgejo.dbUser" . | quote }}
{{- if not .Values.postgres.enabled }}
- name: FORGEJO__database__SSL_MODE
  value: {{ .Values.externalPostgres.sslMode | quote }}
{{- else }}
- name: FORGEJO__database__SSL_MODE
  value: "disable"
{{- end }}
- name: FORGEJO__database__PASSWD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.existingSecret | quote }}
      key: {{ .Values.secretKeys.dbPassword | quote }}
- name: FORGEJO__security__INSTALL_LOCK
  value: "true"
- name: FORGEJO__security__SECRET_KEY
  valueFrom:
    secretKeyRef:
      name: {{ .Values.existingSecret | quote }}
      key: {{ .Values.secretKeys.secretKey | quote }}
- name: FORGEJO__security__INTERNAL_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ .Values.existingSecret | quote }}
      key: {{ .Values.secretKeys.internalToken | quote }}
- name: FORGEJO__oauth2__JWT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ .Values.existingSecret | quote }}
      key: {{ .Values.secretKeys.jwtSecret | quote }}
- name: FORGEJO__service__DISABLE_REGISTRATION
  value: {{ .Values.forgejo.config.disableRegistration | quote }}
- name: FORGEJO__service__ALLOW_ONLY_EXTERNAL_REGISTRATION
  value: {{ .Values.forgejo.config.allowOnlyExternalRegistration | quote }}
- name: FORGEJO__service__SHOW_REGISTRATION_BUTTON
  value: {{ .Values.forgejo.config.showRegistrationButton | quote }}
- name: FORGEJO__openid__ENABLE_OPENID_SIGNIN
  value: {{ .Values.forgejo.config.enableOpenidSignin | quote }}
- name: FORGEJO__openid__ENABLE_OPENID_SIGNUP
  value: {{ .Values.forgejo.config.enableOpenidSignup | quote }}
- name: FORGEJO__oauth2_client__ENABLE_AUTO_REGISTRATION
  value: {{ .Values.forgejo.config.oauth2EnableAutoRegistration | quote }}
- name: FORGEJO__oauth2_client__ACCOUNT_LINKING
  value: {{ .Values.forgejo.config.oauth2AccountLinking | quote }}
- name: FORGEJO__oauth2_client__UPDATE_AVATAR
  value: {{ .Values.forgejo.config.oauth2UpdateAvatar | quote }}
- name: FORGEJO__ui__DEFAULT_THEME
  value: {{ .Values.forgejo.config.defaultTheme | quote }}
- name: FORGEJO__log__LEVEL
  value: {{ .Values.forgejo.config.logLevel | quote }}
{{- with .Values.forgejo.config.extraEnv }}
{{ toYaml . }}
{{- end }}
{{- end }}
