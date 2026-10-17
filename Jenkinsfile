pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timeout(time: 60, unit: 'MINUTES')
    }

    environment {
        IMAGE_TAG  = "build-${env.BUILD_NUMBER}"
        API_IMAGE  = "vaultai-api:${IMAGE_TAG}"
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
                echo "Building ${API_IMAGE} from api/Dockerfile"
                sh '''
                    set -e
                    docker build -t "${API_IMAGE}" -f api/Dockerfile api/
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
            steps {
                sh '''
                    set -e
                    docker save "${API_IMAGE}" | docker exec -i minikube docker load
                    docker exec minikube docker image inspect "${API_IMAGE}" > /dev/null
                    docker save "${WEB_IMAGE}" | docker exec -i minikube docker load
                    docker exec minikube docker image inspect "${WEB_IMAGE}" > /dev/null
                '''
            }
        }

        stage('Deploy Staging') {
            when { branch 'main' }
            steps {
                withCredentials([file(credentialsId: env.KUBECONFIG_CRED_ID, variable: 'KUBECONFIG')]) {
                    sh '''
                        set -e
                        kubectl apply -k k8s/overlays/staging --kubeconfig="$KUBECONFIG"
                        kubectl set image deployment/vaultai-api vaultai-api=${API_IMAGE} \
                            -n vaultai-staging --kubeconfig="$KUBECONFIG"
                        kubectl set image deployment/vaultai-web vaultai-web=${WEB_IMAGE} \
                            -n vaultai-staging --kubeconfig="$KUBECONFIG"
                        kubectl rollout status deployment/vaultai-api -n vaultai-staging --kubeconfig="$KUBECONFIG" --timeout=180s
                        kubectl rollout status deployment/vaultai-web -n vaultai-staging --kubeconfig="$KUBECONFIG" --timeout=180s
                    '''
                }
            }
        }

        stage('Sync Staging Secret') {
            when { branch 'main' }
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
                            -n vaultai-staging --kubeconfig="$KUBECONFIG" \
                            --dry-run=client -o yaml | kubectl apply -f - --kubeconfig="$KUBECONFIG"
                        kubectl set env deployment/vaultai-api --from=secret/vaultai-secrets \
                            -n vaultai-staging --kubeconfig="$KUBECONFIG"
                    '''
                }
            }
        }

        stage('Staging Smoke Test') {
            when { branch 'main' }
            steps {
                withCredentials([file(credentialsId: env.KUBECONFIG_CRED_ID, variable: 'KUBECONFIG')]) {
                    sh '''
                        set -e
                        kubectl get pods -n vaultai-staging --kubeconfig="$KUBECONFIG"
                        kubectl exec -n vaultai-staging --kubeconfig="$KUBECONFIG" deploy/vaultai-api -- \
                            python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8000/healthz').read().decode())"
                        kubectl exec -n vaultai-staging --kubeconfig="$KUBECONFIG" deploy/vaultai-web -- \
                            wget -qO- http://127.0.0.1/healthz
                    '''
                }
            }
        }

        stage('Approve Production') {
            when { branch 'main' }
            steps {
                timeout(time: 30, unit: 'MINUTES') {
                    input message: "Staging passed for ${env.GIT_COMMIT_SHORT}. Promote ${API_IMAGE} / ${WEB_IMAGE} to PRODUCTION?", ok: 'Deploy to prod'
                }
            }
        }

        stage('Deploy Production') {
            when { branch 'main' }
            steps {
                withCredentials([file(credentialsId: env.KUBECONFIG_CRED_ID, variable: 'KUBECONFIG')]) {
                    sh '''
                        set -e
                        kubectl apply -k k8s/overlays/prod --kubeconfig="$KUBECONFIG"
                        kubectl set image deployment/vaultai-api vaultai-api=${API_IMAGE} \
                            -n vaultai-prod --kubeconfig="$KUBECONFIG"
                        kubectl set image deployment/vaultai-web vaultai-web=${WEB_IMAGE} \
                            -n vaultai-prod --kubeconfig="$KUBECONFIG"
                        kubectl rollout status deployment/vaultai-api -n vaultai-prod --kubeconfig="$KUBECONFIG" --timeout=180s
                        kubectl rollout status deployment/vaultai-web -n vaultai-prod --kubeconfig="$KUBECONFIG" --timeout=180s
                    '''
                }
            }
        }

        stage('Sync Production Secret') {
            when { branch 'main' }
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
                            -n vaultai-prod --kubeconfig="$KUBECONFIG" \
                            --dry-run=client -o yaml | kubectl apply -f - --kubeconfig="$KUBECONFIG"
                        kubectl set env deployment/vaultai-api --from=secret/vaultai-secrets \
                            -n vaultai-prod --kubeconfig="$KUBECONFIG"
                    '''
                }
            }
        }

        stage('Production Smoke Test') {
            when { branch 'main' }
            steps {
                withCredentials([file(credentialsId: env.KUBECONFIG_CRED_ID, variable: 'KUBECONFIG')]) {
                    sh '''
                        set -e
                        kubectl get pods -n vaultai-prod --kubeconfig="$KUBECONFIG"
                        kubectl exec -n vaultai-prod --kubeconfig="$KUBECONFIG" deploy/vaultai-api -- \
                            python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8000/healthz').read().decode())"
                        kubectl exec -n vaultai-prod --kubeconfig="$KUBECONFIG" deploy/vaultai-web -- \
                            wget -qO- http://127.0.0.1/healthz
                    '''
                }
            }
        }
    }

    post {
        success {
            echo "Pipeline complete for ${env.GIT_COMMIT_SHORT}: ${API_IMAGE} and ${WEB_IMAGE} deployed."
        }
        failure {
            echo "Pipeline failed at commit ${env.GIT_COMMIT_SHORT}."
            echo "If staging failed, prod was never touched -- no rollback needed there."
            echo "If prod failed after deploying, roll back with:"
            echo "kubectl rollout undo deployment/vaultai-api -n vaultai-prod"
            echo "kubectl rollout undo deployment/vaultai-web -n vaultai-prod"
        }
        aborted {
            echo "Build aborted -- likely the production approval window (30 min) timed out, or it was manually cancelled."
            echo "Staging remains deployed; production was not touched."
        }
        always {
            cleanWs()
        }
    }
}
