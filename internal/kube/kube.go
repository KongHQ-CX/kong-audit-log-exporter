package kube

import (
	"context"
	"fmt"
	"log"
	"path/filepath"

	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	corev1ac "k8s.io/client-go/applyconfigurations/core/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/util/homedir"
)

func GetSecretExternal(name, namespace string) (*map[string][]byte, error) {
	var kubeconfig string
	if home := homedir.HomeDir(); home != "" {
		kubeconfig = filepath.Join(home, ".kube", "config")
	} else {
		log.Fatalln("Could not determine user home")
	}

	// use the current context in kubeconfig
	config, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
	if err != nil {
		panic(err.Error())
	}

	// create the clientset
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		panic(err.Error())
	}
	secretsClient := clientset.CoreV1().Secrets(namespace)

	secret, err := secretsClient.Get(context.TODO(), name, metav1.GetOptions{})

	if errors.IsNotFound(err) {
		return nil, nil
	} else if err != nil {
		return nil, err
	}

	return &secret.Data, nil
}

func CreateSecretInternal(data map[string][]byte, name, namespace string) {
	// creates the in-cluster config
	config, err := rest.InClusterConfig()
	if err != nil {
		panic(err.Error())
	}
	// creates the clientset
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		panic(err.Error())
	}

	secretsClient := clientset.CoreV1().Secrets(namespace)

	applyConfiguration := corev1ac.Secret(name, namespace)
	applyConfiguration.Data = data

	// Create Deployment
	result, err := secretsClient.Apply(context.TODO(), applyConfiguration, metav1.ApplyOptions{
		FieldManager: "application/apply-patch",
	})
	if err != nil {
		panic(err)
	}
	fmt.Printf("INFO: Updated tracking secret %q.\n", result.GetObjectMeta().GetName())
}

func CreateSecretExternal(data map[string][]byte, name, namespace string) {
	var kubeconfig string
	if home := homedir.HomeDir(); home != "" {
		kubeconfig = filepath.Join(home, ".kube", "config")
	} else {
		log.Fatalln("Could not determine user home")
	}

	// use the current context in kubeconfig
	config, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
	if err != nil {
		panic(err.Error())
	}

	// create the clientset
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		panic(err.Error())
	}
	secretsClient := clientset.CoreV1().Secrets(namespace)

	applyConfiguration := corev1ac.Secret(name, namespace)
	applyConfiguration.Data = data

	// Create Deployment
	result, err := secretsClient.Apply(context.TODO(), applyConfiguration, metav1.ApplyOptions{
		FieldManager: "application/apply-patch",
	})
	if err != nil {
		panic(err)
	}
	fmt.Printf("INFO: Updated tracking secret %q.\n", result.GetObjectMeta().GetName())
}

func ListPodsInternal() {
	// creates the in-cluster config
	config, err := rest.InClusterConfig()
	if err != nil {
		panic(err.Error())
	}
	// creates the clientset
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		panic(err.Error())
	}

	// get pods in all the namespaces by omitting namespace
	// Or specify namespace to get pods in particular namespace
	pods, err := clientset.CoreV1().Pods("").List(context.TODO(), metav1.ListOptions{})
	if err != nil {
		panic(err.Error())
	}
	fmt.Printf("There are %d pods in the cluster\n", len(pods.Items))

}

func ListPodsExternal() {
	var kubeconfig string
	if home := homedir.HomeDir(); home != "" {
		kubeconfig = filepath.Join(home, ".kube", "config")
	} else {
		log.Fatalln("Could not determine user home")
	}

	// use the current context in kubeconfig
	config, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
	if err != nil {
		panic(err.Error())
	}

	// create the clientset
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		panic(err.Error())
	}

	pods, err := clientset.CoreV1().Pods("").List(context.TODO(), metav1.ListOptions{})
	if err != nil {
		panic(err.Error())
	}
	fmt.Printf("There are %d pods in the cluster\n", len(pods.Items))

}
