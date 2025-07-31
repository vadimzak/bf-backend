import { makeAutoObservable } from 'mobx';

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
    // Import dynamically to avoid circular dependency
    const { fetchAuthSession } = await import('aws-amplify/auth');
    
    try {
      const session = await fetchAuthSession();
      const accessToken = session.tokens?.accessToken?.toString();
      
      if (!accessToken) {
        throw new Error('No access token available');
      }

      return {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      };
    } catch (error) {
      console.error('Failed to get auth token:', error);
      throw new Error('Authentication failed');
    }
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