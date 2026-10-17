pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timeout(time: 30, unit: 'MINUTES')
    }

    parameters {
        string(name: 'IMAGE_NAME', defaultValue: 'vaultai-api', description: 'API container image name')
        string(name: 'K8S_NAMESPACE', defaultValue: 'vaultai-staging', description: 'Target Kubernetes namespace (vaultai-staging or vaultai-prod)')
        string(name: 'K8S_DEPLOYMENT', defaultValue: 'vaultai-api', description: 'API deployment object to update')
    }

    environment {
        IMAGE_TAG  = "build-${env.BUILD_NUMBER}"
        FULL_IMAGE = "${params.IMAGE_NAME}:${IMAGE_TAG}"
        WEB_IMAGE  = "vaultai-web:${IMAGE_TAG}"
        KUBECONFIG_CRED_ID = 'minikube-kubeconfig'
        ANTHROPIC_CRED_ID  = 'vaultai-anthropic-key'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_COMMIT_SHORT = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
                    echo "Building commit ${env.GIT_COMMIT_SHORT}"
                }
            }
        }

        stage('Build API Image') {
            steps {
                echo "Building ${FULL_IMAGE} from api/Dockerfile"
                sh '''
                    set -e
                    docker build -t "${FULL_IMAGE}" -f api/Dockerfile api/
                '''
            }
        }

        stage('Build Web Image') {
            steps {
                echo "Building ${WEB_IMAGE} from app/Dockerfile"
                sh '''
                    set -e
                    docker build -t "${WEB_IMAGE}" -f app/Dockerfile .
                '''
            }
        }

        stage('Load Images into Minikube') {
            // Local-dev workaround for the single-node minikube cluster, which has
            // no container registry. In production this stage becomes "docker push"
            // to a real registry (GHCR/ECR/GCR) and the nodes pull from it.
            steps {
                sh '''
                    set -e
                    docker save "${FULL_IMAGE}" | docker exec -i minikube docker load
                    docker exec minikube docker image inspect "${FULL_IMAGE}" > /dev/null
                    docker save "${WEB_IMAGE}" | docker exec -i minikube docker load
                    docker exec minikube docker image inspect "${WEB_IMAGE}" > /dev/null
                '''
            }
        }

        stage('Sync API Secret') {
            steps {
                withCredentials([
                    file(credentialsId: env.KUBECONFIG_CRED_ID, variable: 'KUBECONFIG'),
                    string(credentialsId: env.ANTHROPIC_CRED_ID, variable: 'ANTHROPIC_KEY')
                ]) {
                    sh '''
                        set +x
                        set -e
                        kubectl create secret generic vaultai-secrets \
                            --from-literal=ANTHROPIC_API_KEY="$ANTHROPIC_KEY" \
                            -n ${K8S_NAMESPACE} --kubeconfig="$KUBECONFIG" \
                            --dry-run=client -o yaml | kubectl apply -f - --kubeconfig="$KUBECONFIG"
                        kubectl set env deployment/${K8S_DEPLOYMENT} --from=secret/vaultai-secrets \
                            -n ${K8S_NAMESPACE} --kubeconfig="$KUBECONFIG"
                    '''
                }
            }
        }

        stage('Deploy API') {
            steps {
                withCredentials([file(credentialsId: env.KUBECONFIG_CRED_ID, variable: 'KUBECONFIG')]) {
                    sh '''
                        set -e
                        kubectl set image deployment/${K8S_DEPLOYMENT} \
                            ${IMAGE_NAME}=${FULL_IMAGE} \
                            -n ${K8S_NAMESPACE} \
                            --kubeconfig="$KUBECONFIG"
                        kubectl rollout status deployment/${K8S_DEPLOYMENT} \
                            -n ${K8S_NAMESPACE} \
                            --kubeconfig="$KUBECONFIG" \
                            --timeout=180s
                    '''
                }
            }
        }

        stage('Deploy Web') {
            steps {
                withCredentials([file(credentialsId: env.KUBECONFIG_CRED_ID, variable: 'KUBECONFIG')]) {
                    sh '''
                        set -e
                        kubectl set image deployment/vaultai-web \
                            vaultai-web=${WEB_IMAGE} \
                            -n ${K8S_NAMESPACE} \
                            --kubeconfig="$KUBECONFIG"
                        kubectl rollout status deployment/vaultai-web \
                            -n ${K8S_NAMESPACE} \
                            --kubeconfig="$KUBECONFIG" \
                            --timeout=180s
                    '''
                }
            }
        }

        stage('Smoke Test') {
            steps {
                withCredentials([file(credentialsId: env.KUBECONFIG_CRED_ID, variable: 'KUBECONFIG')]) {
                    sh '''
                        set -e
                        kubectl get pods -n ${K8S_NAMESPACE} --kubeconfig="$KUBECONFIG"
                        kubectl exec -n ${K8S_NAMESPACE} --kubeconfig="$KUBECONFIG" deploy/${K8S_DEPLOYMENT} -- \
                            python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8000/healthz').read().decode())"
                        kubectl exec -n ${K8S_NAMESPACE} --kubeconfig="$KUBECONFIG" deploy/vaultai-web -- \
                            wget -qO- http://localhost/healthz
                    '''
                }
            }
        }
    }

    post {
        success {
            echo "Deployed ${FULL_IMAGE} and ${WEB_IMAGE} to ${params.K8S_NAMESPACE} successfully."
        }
        failure {
            echo "Pipeline failed at commit ${env.GIT_COMMIT_SHORT}. Rollback commands:"
            echo "kubectl rollout undo deployment/${params.K8S_DEPLOYMENT} -n ${params.K8S_NAMESPACE}"
            echo "kubectl rollout undo deployment/vaultai-web -n ${params.K8S_NAMESPACE}"
        }
        always {
            cleanWs()
        }
    }
}
