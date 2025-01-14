#! /bin/bash

PIPELINE_NS=mq00-pipeline
PIPELINE_SA=mq00pipeline

CRB_PL_ADMIN=mq00pipelinetektonpipelinesadminbinding
CRB_TRIG_ADMIN=mq00pipelinetektontriggersadminbinding
CRB_PULLER=mq00pipelinepullerbinding
CRB_BUILDER=mq00pipelinebuilderinding
CRB_QM_EDIT=mq00pipelineqmeditbinding
CRB_QM_VIEW=mq00pipelineqmviewbinding
CRB_VIEW=mq00pipelineviewbinding
CRB_EDIT=mq00pipelineeditbinding

MQ_NS=<insert MQ namespace here>
PN_NS=<insert Platform Navigator namespace here>
REG_SECRET=ibm-entitlement-key

GIT_SECRET_NAME=user-at-github

# Insert your Git Access Token below
GIT_TOKEN=<insert your git token here>

# Insert your Git UserName here
GIT_USERNAME=<insert your git user name here>

# Create the pipeline namespace
kubectl create ns $PIPELINE_NS

# Change to the new namespace
oc project $PIPELINE_NS

# Copy docker-registry secret to the new namespace
oc get secret $REG_SECRET -n $MQ_NS --export -o yaml | oc apply -n $PIPELINE_NS -f -

# install tekton pipelines v0.14.3
kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/previous/v0.14.3/release.yaml

# install tekton triggers v0.7.0
kubectl apply --filename https://storage.googleapis.com/tekton-releases/triggers/previous/v0.7.0/release.yaml

# create the git secret
oc secret new-basicauth $GIT_SECRET_NAME --username=$GIT_USERNAME --password $GIT_TOKEN

# annotate the secret
kubectl annotate secret $GIT_SECRET_NAME tekton.dev/git-0=github.com

# create serviceaccount to run the pipeline and associate the git secret with the serviceaccount
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $PIPELINE_SA
secrets:
- name: $GIT_SECRET_NAME
EOF

# Create the ClusterRole
cat << EOF | kubectl apply -f -
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: tekton-pipelines-admin
rules:
# Permissions for every EventListener deployment to function
- apiGroups: ["triggers.tekton.dev"]
  resources: ["eventlisteners", "triggerbindings", "triggertemplates"]
  verbs: ["get"]
- apiGroups: [""]
  # secrets are only needed for Github/Gitlab interceptors, serviceaccounts only for per trigger authorization
  resources: ["configmaps", "secrets", "serviceaccounts"]
  verbs: ["get", "list", "watch"]
# Permissions to create resources in associated TriggerTemplates
- apiGroups: ["tekton.dev"]
  resources: ["pipelineruns", "pipelineresources", "taskruns"]
  verbs: ["create"]
EOF

# Create these ClusterRoleBindings
oc create clusterrolebinding $CRB_PL_ADMIN --clusterrole=tekton-pipelines-admin --serviceaccount=$PIPELINE_NS:$PIPELINE_SA
oc create clusterrolebinding $CRB_TRIG_ADMIN --clusterrole=tekton-triggers-admin --serviceaccount=$PIPELINE_NS:$PIPELINE_SA

oc create clusterrolebinding $CRB_PULLER --clusterrole=system:image-puller --serviceaccount=$PIPELINE_NS:$PIPELINE_SA
oc create clusterrolebinding $CRB_BUILDER --clusterrole=system:image-builder --serviceaccount=$PIPELINE_NS:$PIPELINE_SA

oc create clusterrolebinding $CRB_QM_EDIT --clusterrole=queuemanagers.mq.ibm.com-v1beta1-edit --serviceaccount=$PIPELINE_NS:$PIPELINE_SA
oc create clusterrolebinding $CRB_QM_VIEW --clusterrole=queuemanagers.mq.ibm.com-v1beta1-view --serviceaccount=$PIPELINE_NS:$PIPELINE_SA

oc create clusterrolebinding $CRB_QM_EDIT --clusterrole=queuemanagers.mq.ibm.com-v1beta1-edit --serviceaccount=$MQ_NS:$PIPELINE_SA
oc create clusterrolebinding $CRB_QM_VIEW --clusterrole=queuemanagers.mq.ibm.com-v1beta1-view --serviceaccount=$MQ_NS:$PIPELINE_SA

oc create clusterrolebinding $CRB_VIEW --clusterrole=view --serviceaccount=$PIPELINE_NS:$PIPELINE_SA
oc create clusterrolebinding $CRB_EDIT --clusterrole=edit --serviceaccount=$PIPELINE_NS:$PIPELINE_SA

oc create clusterrolebinding $CRB_VIEW --clusterrole=view --serviceaccount=$MQ_NS:$PIPELINE_SA
oc create clusterrolebinding $CRB_EDIT --clusterrole=edit --serviceaccount=$MQ_NS:$PIPELINE_SA

# Add the serviceaccount to privileged SecurityContextConstraint
oc adm policy add-scc-to-user privileged system:serviceaccount:$PIPELINE_NS:$PIPELINE_SA
oc adm policy add-scc-to-user privileged system:serviceaccount:$MQ_NS:$PIPELINE_SA

# Add tekton resources
oc apply -f ./tekton/pipelines/
oc apply -f ./tekton/resources/
oc apply -f ./tekton/tasks/
oc apply -f ./tekton/triggers/

# Create route for webhook
cat << EOF | kubectl apply -f -
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  labels:
    app.kubernetes.io/managed-by: EventListener
    app.kubernetes.io/part-of: Triggers
    eventlistener: el-cicd-mq
  name: el-el-cicd-mq-hook-route
spec:
  port:
    targetPort: http-listener
  tls:
    insecureEdgeTerminationPolicy: Redirect
    termination: edge
  to:
    kind: Service
    name: el-el-cicd-mq
EOF
