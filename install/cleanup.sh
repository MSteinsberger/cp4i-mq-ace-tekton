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

MQ_NS=cp4i-mq
PN_NS=cp4i
REG_SECRET=ibm-entitlement-key

# Change to the navigator namespace
oc project $PN_NS

# Delete the pipeline namespace
kubectl delete ns $PIPELINE_NS

