/*
Copyright 2024 Corewire.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

// Package main is the entry point for the provider-litellm code generator.
// Run it with the repository root as the argument to regenerate all managed
// resource types, controllers, and example manifests.
package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/crossplane/upjet/v2/pkg/pipeline"

	"github.com/corewire/provider-litellm/config"
)

func main() {
	if len(os.Args) < 2 || os.Args[1] == "" {
		panic("root directory is required to be given as argument")
	}
	rootDir := os.Args[1]
	absRootDir, err := filepath.Abs(rootDir)
	if err != nil {
		panic(fmt.Sprintf("cannot calculate the absolute path with %s", rootDir))
	}
	provider, err := config.GetProvider(true)
	if err != nil {
		panic(fmt.Sprintf("cannot get provider configuration: %s", err))
	}
	// Pass nil for the namespaced provider — provider-litellm only uses
	// cluster-scoped resources. When namespaced resources are needed in the
	// future, add a GetProviderNamespaced function to config/provider.go and
	// pass it here.
	pipeline.Run(provider, nil, absRootDir)
}
