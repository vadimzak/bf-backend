import { makeAutoObservable } from 'mobx';
import { getAuthHeaders } from '../utils/auth-headers';

export interface Project {
  id: string;
  name: string;
  description?: string;
  createdAt: string;
  updatedAt: string;
}

export class ProjectStore {
  projects: Project[] = [];
  currentProject: Project | null = null;
  loading = false;
  error: string | null = null;

  constructor() {
    makeAutoObservable(this);
  }

  setProjects(projects: Project[]) {
    this.projects = projects;
  }

  getMostRecentProject(): Project | null {
    if (this.projects.length === 0) return null;
    
    // Sort by updatedAt timestamp (most recent first)
    const sortedProjects = [...this.projects].sort((a, b) => 
      new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime()
    );
    
    return sortedProjects[0];
  }

  autoSelectProject() {
    if (!this.currentProject && this.projects.length > 0) {
      const mostRecent = this.getMostRecentProject();
      if (mostRecent) {
        this.setCurrentProject(mostRecent);
      }
    }
  }

  setCurrentProject(project: Project | null) {
    this.currentProject = project;
  }

  addProject(project: Project) {
    this.projects.push(project);
  }

  updateProject(projectId: string, updates: Partial<Project>) {
    const index = this.projects.findIndex(p => p.id === projectId);
    if (index >= 0) {
      this.projects[index] = { ...this.projects[index], ...updates };
      if (this.currentProject?.id === projectId) {
        this.currentProject = { ...this.currentProject, ...updates };
      }
    }
  }

  removeProject(projectId: string) {
    this.projects = this.projects.filter(p => p.id !== projectId);
    if (this.currentProject?.id === projectId) {
      this.currentProject = null;
    }
  }

  setLoading(loading: boolean) {
    this.loading = loading;
  }

  setError(error: string | null) {
    this.error = error;
  }

  async getAuthHeaders(): Promise<HeadersInit> {
    return getAuthHeaders();
  }

  async fetchProjects() {
    this.setLoading(true);
    try {
      const headers = await this.getAuthHeaders();
      const response = await fetch('/api/protected/projects', {
        method: 'GET',
        headers,
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const result = await response.json();
      if (result.success) {
        this.setProjects(result.data.projects || []);
        
        // Auto-select the most recent project if none is currently selected
        this.autoSelectProject();
      } else {
        throw new Error(result.error || 'Failed to fetch projects');
      }
      
      this.setError(null);
    } catch (error) {
      console.error('Failed to fetch projects:', error);
      this.setError(error instanceof Error ? error.message : 'Failed to fetch projects');
    } finally {
      this.setLoading(false);
    }
  }

  async createProject(name: string, description?: string) {
    this.setLoading(true);
    try {
      const headers = await this.getAuthHeaders();
      const response = await fetch('/api/protected/projects', {
        method: 'POST',
        headers,
        body: JSON.stringify({ name, description }),
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const result = await response.json();
      if (result.success) {
        this.addProject(result.data.project);
        this.setCurrentProject(result.data.project);
      } else {
        throw new Error(result.error || 'Failed to create project');
      }
      
      this.setError(null);
      return result.data.project;
    } catch (error) {
      console.error('Failed to create project:', error);
      this.setError(error instanceof Error ? error.message : 'Failed to create project');
      throw error;
    } finally {
      this.setLoading(false);
    }
  }

  async updateProjectById(projectId: string, updates: Partial<Project>) {
    this.setLoading(true);
    try {
      const headers = await this.getAuthHeaders();
      const response = await fetch(`/api/protected/projects/${projectId}`, {
        method: 'PUT',
        headers,
        body: JSON.stringify(updates),
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const result = await response.json();
      if (result.success) {
        this.updateProject(projectId, result.data.project);
      } else {
        throw new Error(result.error || 'Failed to update project');
      }
      
      this.setError(null);
    } catch (error) {
      console.error('Failed to update project:', error);
      this.setError(error instanceof Error ? error.message : 'Failed to update project');
      throw error;
    } finally {
      this.setLoading(false);
    }
  }

  async deleteProject(projectId: string) {
    this.setLoading(true);
    try {
      const headers = await this.getAuthHeaders();
      const response = await fetch(`/api/protected/projects/${projectId}`, {
        method: 'DELETE',
        headers,
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const result = await response.json();
      if (result.success) {
        this.removeProject(projectId);
      } else {
        throw new Error(result.error || 'Failed to delete project');
      }
      
      this.setError(null);
    } catch (error) {
      console.error('Failed to delete project:', error);
      this.setError(error instanceof Error ? error.message : 'Failed to delete project');
      throw error;
    } finally {
      this.setLoading(false);
    }
  }
}