package wrapper

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

type sharedState struct {
	data       []byte
	mode       os.FileMode
	agents     []string
	start, end int
}

func stateError(err error) int {
	return errorExit("cannot clean shared state: " + err.Error())
}

func readState(home string) (sharedState, error) {
	path := filepath.Join(home, ".gentle-ai", "state.json")
	file, err := os.Open(path)
	if os.IsNotExist(err) {
		return sharedState{}, nil
	}
	if err != nil {
		return sharedState{}, err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return sharedState{}, err
	}
	data, err := io.ReadAll(file)
	if err != nil {
		return sharedState{}, err
	}
	state := sharedState{data: data, mode: info.Mode().Perm()}
	dec := json.NewDecoder(bytes.NewReader(data))
	token, err := dec.Token()
	if err != nil {
		return sharedState{}, err
	}
	if token != json.Delim('{') {
		return sharedState{}, fmt.Errorf("state must be a JSON object")
	}
	// Decode only the owned field. Remember its exact byte span rather than
	// reserializing other fields (which can contain arbitrary-precision numbers).
	// As in the legacy JSON parser, the last duplicate key is effective.
	for dec.More() {
		key, err := dec.Token()
		if err != nil {
			return sharedState{}, err
		}
		start := int(dec.InputOffset())
		var raw json.RawMessage
		if err := dec.Decode(&raw); err != nil {
			return sharedState{}, err
		}
		if key == "installed_agents" {
			for start < len(data) && (data[start] == ':' || data[start] == ' ' || data[start] == '\n' || data[start] == '\r' || data[start] == '\t') {
				start++
			}
			state.start, state.end = start, int(dec.InputOffset())
			// Delay validation until all keys are read, preserving last-key wins.
			state.agents = nil
		}
	}
	if _, err := dec.Token(); err != nil {
		return sharedState{}, err
	}
	var trailing json.RawMessage
	if err := dec.Decode(&trailing); err != io.EOF {
		if err == nil {
			err = fmt.Errorf("unexpected data after state object")
		}
		return sharedState{}, err
	}
	if state.end > 0 {
		raw := data[state.start:state.end]
		var items []json.RawMessage
		invalid := fmt.Errorf("installed_agents must be a list of strings")
		if len(raw) == 0 || raw[0] != '[' || json.Unmarshal(raw, &items) != nil {
			return sharedState{}, invalid
		}
		for _, item := range items {
			var value string
			if len(item) == 0 || item[0] != '"' || json.Unmarshal(item, &value) != nil {
				return sharedState{}, invalid
			}
			state.agents = append(state.agents, value)
		}
	}
	return state, nil
}

func companionAgent(agent string) bool {
	return agent == "command-code" || agent == "commandcode"
}

func (s sharedState) officialAgents() string {
	seen := make(map[string]bool)
	var agents []string
	for _, agent := range s.agents {
		if !companionAgent(agent) && !seen[agent] {
			seen[agent] = true
			agents = append(agents, agent)
		}
	}
	return strings.Join(agents, ",")
}

func cleanState(home string) error {
	state, err := readState(home)
	if err != nil {
		return err
	}
	cleaned := make([]string, 0, len(state.agents))
	for _, agent := range state.agents {
		if !companionAgent(agent) {
			cleaned = append(cleaned, agent)
		}
	}
	if len(cleaned) == len(state.agents) {
		return nil // Includes missing state: preserve bytes, inode and mtime.
	}
	raw, err := json.Marshal(cleaned)
	if err != nil {
		return err
	}
	path := filepath.Join(home, ".gentle-ai", "state.json")
	file, err := os.CreateTemp(filepath.Dir(path), ".gentle-cc-")
	if err != nil {
		return err
	}
	name := file.Name()
	defer os.Remove(name)
	defer file.Close()
	if err := file.Chmod(state.mode); err != nil {
		return err
	}
	for _, part := range [][]byte{state.data[:state.start], raw, state.data[state.end:]} {
		if _, err := file.Write(part); err != nil {
			return err
		}
	}
	if err := file.Sync(); err != nil {
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	return replaceFile(name, path)
}
