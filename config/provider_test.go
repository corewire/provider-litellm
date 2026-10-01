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

package config

import "testing"

func TestProviderIncludesOnlyConfiguredResources(t *testing.T) {
	for _, generationProvider := range []bool{true, false} {
		provider, err := GetProvider(generationProvider)
		if err != nil {
			t.Fatal(err)
		}
		if len(provider.Resources) != len(ExternalNameConfigs) {
			t.Errorf("generation=%v: got %d resources, want %d", generationProvider, len(provider.Resources), len(ExternalNameConfigs))
		}
		for resourceName := range provider.Resources {
			if _, configured := ExternalNameConfigs[resourceName]; !configured {
				t.Errorf("generation=%v: unconfigured resource %s was included", generationProvider, resourceName)
			}
		}
	}
}
