pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timeout(time: 30, unit: 'MINUTES')
    }

    parameters {
        string(name: 'IMAGE_NAME', defaultValue: 'vaultai-api', description: 'Container image name')
        string(name: 'K8S_NAMESPACE', defaultValue: 'vaultai-staging', description: 'Target Kubernetes namespace (vaultai-staging or vaultai-prod)')
        string(name: 'K8S_DEPLOYMENT', defaultValue: 'vaultai-api', description: 'Deployment object to update')
    }

    environment {
        IMAGE_TAG  = "build-${env.BUILD_NUMBER}"
        FULL_IMAGE = "${params.IMAGE_NAME}:${IMAGE_TAG}"
        KUBECONFIG_CRED_ID = 'minikube-kubeconfig'
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

        stage('Build Image') {
            steps {
                echo "Building ${FULL_IMAGE} from api/Dockerfile"
                sh '''
                    set -e
                    docker build -t "${FULL_IMAGE}" -f api/Dockerfile api/
                '''
            }
        }

        stage('Load Image into Minikube') {
            steps {
                echo "Loading ${FULL_IMAGE} into the minikube cluster's local image cache"
                sh '''
                    set -e
                    minikube image load "${FULL_IMAGE}"
                '''
            }
        }

        stage('Deploy to Kubernetes') {
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

        stage('Smoke Test') {
            steps {
                withCredentials([file(credentialsId: env.KUBECONFIG_CRED_ID, variable: 'KUBECONFIG')]) {
                    sh '''
                        kubectl get pods -n ${K8S_NAMESPACE} -l app=${IMAGE_NAME} --kubeconfig="$KUBECONFIG"
                    '''
                }
            }
        }
    }

    post {
        success {
            echo "Deployed ${FULL_IMAGE} to ${params.K8S_NAMESPACE}/${params.K8S_DEPLOYMENT} successfully."
        }
        failure {
            echo "Pipeline failed at commit ${env.GIT_COMMIT_SHORT}. Rollback command:"
            echo "kubectl rollout undo deployment/${params.K8S_DEPLOYMENT} -n ${params.K8S_NAMESPACE}"
        }
        always {
            cleanWs()
        }
    }
}
